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
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $upgradeDbName = "dbatoolsci_upgrade_output"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $upgradeDbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $upgradeDbName -Confirm:$false -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output validation" {
        BeforeAll {
            $result = Invoke-DbaDbUpgrade -SqlInstance $TestConfig.InstanceSingle -Database $upgradeDbName -Force
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected output properties" {
            $expectedProps = @(
                "ComputerName", "InstanceName", "SqlInstance", "Database",
                "OriginalCompatibility", "CurrentCompatibility", "Compatibility",
                "TargetRecoveryTime", "DataPurity", "UpdateUsage", "UpdateStats", "RefreshViews"
            )
            foreach ($prop in $expectedProps) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present on the output object"
            }
        }
    }
}