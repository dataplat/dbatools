#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaFilestream",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

<#
    The below statement stays in for every test you build.
#>
<#
    Unit test is required for any command added
#>
Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Getting FileStream Level" {
        It "Should have changed the FileStream Level" {
            $results = Get-DbaFilestream -SqlInstance $TestConfig.instance2
            $results.InstanceAccess | Should -BeIn "Disabled", "T-SQL access enabled", "Full access enabled"
        }
    }
}