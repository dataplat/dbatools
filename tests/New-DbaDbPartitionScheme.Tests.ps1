#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbPartitionScheme",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/New-DbaDbPartitionScheme.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Name",
                "PartitionFunction",
                "FileGroup",
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

        $dbBasic = "dbatoolsci_newps_$random"
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbBasic

        $intType = New-Object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::Int)
        # A scheme needs a function; RANGE RIGHT with 3 boundaries => 4 partitions.
        $null = New-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbBasic -Name "pfForScheme" -InputParameterType $intType -RangeType Right -RangeValues @(1, 100, 1000)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $dbBasic -Confirm:$false -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the create and changes nothing" {
            $splatWhatIf = @{
                SqlInstance       = $InstanceSingle
                Database          = $dbBasic
                Name              = "psWhatIf"
                PartitionFunction = "pfForScheme"
                FileGroup         = "PRIMARY"
                WhatIf            = $true
            }
            New-DbaDbPartitionScheme @splatWhatIf
            $created = Get-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbBasic -PartitionScheme "psWhatIf" -ErrorAction SilentlyContinue
            $created | Should -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Creates a scheme with a single filegroup expanded across all partitions" {
            # The single-filegroup expansion is this command's job (SMO has no ALL TO shorthand).
            $splatBasic = @{
                SqlInstance       = $InstanceSingle
                Database          = $dbBasic
                Name              = "psBasic"
                PartitionFunction = "pfForScheme"
                FileGroup         = "PRIMARY"
                EnableException   = $true
                Confirm           = $false
            }
            $result = New-DbaDbPartitionScheme @splatBasic
            $result.Name | Should -Be "psBasic"
            $result.PartitionFunction | Should -Be "pfForScheme"
            $result.ComputerName | Should -Not -BeNullOrEmpty
            (Get-DbaDbPartitionScheme -SqlInstance $InstanceSingle -Database $dbBasic -PartitionScheme "psBasic").Name | Should -Be "psBasic"
        }

        It "Creates a scheme in multiple piped databases (N in, N out)" {
            $dbPipe1 = "dbatoolsci_newps_p1_$random"
            $dbPipe2 = "dbatoolsci_newps_p2_$random"
            $pipeDatabases = @($dbPipe1, $dbPipe2)
            $intTypeLocal = New-Object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::Int)
            try {
                $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $pipeDatabases -EnableException
                foreach ($pipeDb in $pipeDatabases) {
                    $null = New-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $pipeDb -Name "pfPipe" -InputParameterType $intTypeLocal -RangeType Right -RangeValues @(1, 100, 1000) -EnableException
                }
                $results = Get-DbaDatabase -SqlInstance $InstanceSingle -Database $pipeDatabases |
                    New-DbaDbPartitionScheme -Name "psPipe" -PartitionFunction "pfPipe" -FileGroup "PRIMARY" -Confirm:$false
                ($results | Measure-Object).Count | Should -Be 2
                $results.Name | Sort-Object -Unique | Should -Be "psPipe"
            } finally {
                Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $pipeDatabases -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Name              = "psNeither"
                PartitionFunction = "pfForScheme"
                FileGroup         = "PRIMARY"
                Confirm           = $false
                WarningAction     = "SilentlyContinue"
                WarningVariable   = "warnNeither"
            }
            $results = New-DbaDbPartitionScheme @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns when the partition function does not exist" {
            $splatNoFunc = @{
                SqlInstance       = $InstanceSingle
                Database          = $dbBasic
                Name              = "psNoFunc"
                PartitionFunction = "pfDoesNotExist"
                FileGroup         = "PRIMARY"
                Confirm           = $false
                WarningAction     = "SilentlyContinue"
                WarningVariable   = "warnNoFunc"
            }
            $results = New-DbaDbPartitionScheme @splatNoFunc
            $warnNoFunc | Should -BeLike "*does not exist*"
            $results | Should -BeNullOrEmpty
        }
    }
}
