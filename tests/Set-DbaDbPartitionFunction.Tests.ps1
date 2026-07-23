#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbPartitionFunction",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbPartitionFunction.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "PartitionFunction",
                "MergeRangePartition",
                "SplitRangePartition",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $dbName = "dbatoolsci_setpf_$random"
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbName

        $intType = New-Object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::Int)
        # RANGE RIGHT with 3 boundaries => 4 partitions; a scheme with NEXT USED is needed for split.
        $null = New-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -Name "pfSplit" -InputParameterType $intType -RangeType Right -RangeValues @(1, 100, 1000)
        $null = New-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -Name "pfMerge" -InputParameterType $intType -RangeType Right -RangeValues @(1, 100, 1000)
        $null = New-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -Name "pfWhatIf" -InputParameterType $intType -RangeType Right -RangeValues @(1, 100, 1000)
        $null = New-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -Name "psSplit" -PartitionFunction "pfSplit" -FileGroup "PRIMARY"
        $null = New-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -Name "psWhatIf" -PartitionFunction "pfWhatIf" -FileGroup "PRIMARY"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the split and does not move a boundary" {
            # The operation fires immediately in SMO, so the distinguishing assertion is that NumberOfPartitions
            # did not change under -WhatIf.
            $before = (Get-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -PartitionFunction "pfWhatIf").NumberOfPartitions
            Set-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme "psWhatIf" -NextUsedFileGroup "PRIMARY" -Confirm:$false
            Set-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -PartitionFunction "pfWhatIf" -SplitRangePartition 500 -WhatIf
            $after = (Get-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -PartitionFunction "pfWhatIf").NumberOfPartitions
            $after | Should -Be $before
        }
    }

    Context "Command behavior" {
        It "Splits a range partition after NEXT USED is set (NumberOfPartitions grows)" {
            $before = (Get-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -PartitionFunction "pfSplit").NumberOfPartitions
            Set-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme "psSplit" -NextUsedFileGroup "PRIMARY" -Confirm:$false
            $result = Set-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -PartitionFunction "pfSplit" -SplitRangePartition 500 -EnableException -Confirm:$false
            $result.Name | Should -Be "pfSplit"
            $result.NumberOfPartitions | Should -Be ($before + 1)
        }

        It "Merges a range partition back (NumberOfPartitions shrinks)" {
            $before = (Get-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -PartitionFunction "pfMerge").NumberOfPartitions
            $result = Set-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -PartitionFunction "pfMerge" -MergeRangePartition 100 -EnableException -Confirm:$false
            $result.NumberOfPartitions | Should -Be ($before - 1)
        }

        It "Merges a range partition in multiple piped functions (N in, N out)" {
            $intTypeLocal = New-Object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::Int)
            $pfPipe1 = "pfPipeMerge1_$random"
            $pfPipe2 = "pfPipeMerge2_$random"
            $null = New-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -Name $pfPipe1 -InputParameterType $intTypeLocal -RangeType Right -RangeValues @(1, 100, 1000) -EnableException
            $null = New-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -Name $pfPipe2 -InputParameterType $intTypeLocal -RangeType Right -RangeValues @(1, 100, 1000) -EnableException
            $results = Get-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -PartitionFunction $pfPipe1, $pfPipe2 |
                Set-DbaDbPartitionFunction -MergeRangePartition 100 -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            $results.NumberOfPartitions | Sort-Object -Unique | Should -Be 3
        }
    }

    Context "Failure paths" {
        It "Refuses both -MergeRangePartition and -SplitRangePartition together" {
            $splatBoth = @{
                SqlInstance         = $InstanceSingle
                Database            = $dbName
                PartitionFunction   = "pfMerge"
                MergeRangePartition = 1
                SplitRangePartition = 500
                Confirm             = $false
                WarningAction       = "SilentlyContinue"
                WarningVariable     = "warnBoth"
            }
            $results = Set-DbaDbPartitionFunction @splatBoth
            $warnBoth | Should -BeLike "*mutually exclusive*"
            $results | Should -BeNullOrEmpty
        }
    }
}
