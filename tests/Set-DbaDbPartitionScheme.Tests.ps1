#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbPartitionScheme",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbPartitionScheme.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "PartitionScheme",
                "NextUsedFileGroup",
                "ResetNextUsedFileGroup",
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

        $dbName = "dbatoolsci_setps_$random"
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbName

        $intType = New-Object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::Int)
        $null = New-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbName -Name "pfForScheme" -InputParameterType $intType -RangeType Right -RangeValues @(1, 100, 1000)
        $null = New-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -Name "psSet" -PartitionFunction "pfForScheme" -FileGroup "PRIMARY"
        $null = New-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -Name "psReset" -PartitionFunction "pfForScheme" -FileGroup "PRIMARY"
        $null = New-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -Name "psWhatIf" -PartitionFunction "pfForScheme" -FileGroup "PRIMARY"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the set and changes nothing" {
            $before = (Get-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme "psWhatIf").NextUsedFileGroup
            Set-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme "psWhatIf" -NextUsedFileGroup "PRIMARY" -WhatIf
            $after = (Get-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme "psWhatIf").NextUsedFileGroup
            $after | Should -Be $before
        }
    }

    Context "Command behavior" {
        It "Sets the NEXT USED filegroup and re-emits the decorated object" {
            $result = Set-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme "psSet" -NextUsedFileGroup "PRIMARY" -EnableException -Confirm:$false
            $result.Name | Should -Be "psSet"
            $result.ComputerName | Should -Not -BeNullOrEmpty
            (Get-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme "psSet").NextUsedFileGroup | Should -Be "PRIMARY"
        }

        It "Resets the NEXT USED filegroup with -ResetNextUsedFileGroup" {
            # First set it, then reset it - reset routes through Alter() (not SMO's broken ResetNextUsed()).
            $null = Set-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme "psReset" -NextUsedFileGroup "PRIMARY" -EnableException -Confirm:$false
            $result = Set-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme "psReset" -ResetNextUsedFileGroup -EnableException -Confirm:$false
            $result.Name | Should -Be "psReset"
            (Get-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme "psReset").NextUsedFileGroup | Should -BeNullOrEmpty
        }

        It "Sets the NEXT USED filegroup on multiple piped schemes (N in, N out)" {
            $psPipe1 = "psPipe1_$random"
            $psPipe2 = "psPipe2_$random"
            $null = New-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -Name $psPipe1 -PartitionFunction "pfForScheme" -FileGroup "PRIMARY" -EnableException
            $null = New-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -Name $psPipe2 -PartitionFunction "pfForScheme" -FileGroup "PRIMARY" -EnableException
            $results = Get-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbName -PartitionScheme $psPipe1, $psPipe2 |
                Set-DbaDbPartitionScheme -NextUsedFileGroup "PRIMARY" -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            $results.NextUsedFileGroup | Sort-Object -Unique | Should -Be "PRIMARY"
        }
    }

    Context "Failure paths" {
        It "Refuses both -NextUsedFileGroup and -ResetNextUsedFileGroup together" {
            $splatBoth = @{
                SqlInstance            = $InstanceSingle
                Database               = $dbName
                PartitionScheme        = "psSet"
                NextUsedFileGroup      = "PRIMARY"
                ResetNextUsedFileGroup = $true
                Confirm                = $false
                WarningAction          = "SilentlyContinue"
                WarningVariable        = "warnBoth"
            }
            $results = Set-DbaDbPartitionScheme @splatBoth
            $warnBoth | Should -BeLike "*mutually exclusive*"
            $results | Should -BeNullOrEmpty
        }
    }
}
