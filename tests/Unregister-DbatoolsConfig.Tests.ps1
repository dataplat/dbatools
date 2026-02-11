#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Unregister-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ConfigurationItem",
                "FullName",
                "Module",
                "Name",
                "Scope"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $null = Set-DbatoolsConfig -FullName "dbatoolsci.unittest.outputtest" -Value "testvalue"
            $null = Register-DbatoolsConfig -FullName "dbatoolsci.unittest.outputtest"
        }

        AfterAll {
            $null = Unregister-DbatoolsConfig -FullName "dbatoolsci.unittest.outputtest" -ErrorAction SilentlyContinue
        }

        It "Returns no output" {
            $result = Unregister-DbatoolsConfig -FullName "dbatoolsci.unittest.outputtest"
            $result | Should -BeNullOrEmpty
        }
    }
}