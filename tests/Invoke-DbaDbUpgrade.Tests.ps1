#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbUpgrade",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "NoCheckDb",
                "NoUpdateUsage",
                "NoUpdateStats",
                "NoRefreshView",
                "AllUserDatabases",
                "Force",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Invoke-DbaDbUpgrade -SqlInstance $TestConfig.instance1 -Database master -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'OriginalCompatibility',
                'CurrentCompatibility',
                'Compatibility',
                'TargetRecoveryTime',
                'DataPurity',
                'UpdateUsage',
                'UpdateStats',
                'RefreshViews'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output with -NoCheckDb" {
        BeforeAll {
            $result = Invoke-DbaDbUpgrade -SqlInstance $TestConfig.instance1 -Database master -NoCheckDb -EnableException
        }

        It "Does not include DataPurity property when -NoCheckDb is specified" {
            $result.PSObject.Properties.Name | Should -Not -Contain 'DataPurity' -Because "-NoCheckDb skips DBCC CHECKDB and should not output DataPurity"
        }
    }

    Context "Output with -NoUpdateUsage" {
        BeforeAll {
            $result = Invoke-DbaDbUpgrade -SqlInstance $TestConfig.instance1 -Database master -NoUpdateUsage -EnableException
        }

        It "Shows 'Skipped' for UpdateUsage when -NoUpdateUsage is specified" {
            $result.UpdateUsage | Should -Be 'Skipped'
        }
    }

    Context "Output with -NoUpdateStats" {
        BeforeAll {
            $result = Invoke-DbaDbUpgrade -SqlInstance $TestConfig.instance1 -Database master -NoUpdateStats -EnableException
        }

        It "Shows 'Skipped' for UpdateStats when -NoUpdateStats is specified" {
            $result.UpdateStats | Should -Be 'Skipped'
        }
    }

    Context "Output with -NoRefreshView" {
        BeforeAll {
            $result = Invoke-DbaDbUpgrade -SqlInstance $TestConfig.instance1 -Database master -NoRefreshView -EnableException
        }

        It "Shows 'Skipped' for RefreshViews when -NoRefreshView is specified" {
            $result.RefreshViews | Should -Be 'Skipped'
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>