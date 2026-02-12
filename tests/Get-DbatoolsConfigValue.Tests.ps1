#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsConfigValue",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FullName",
                "Fallback",
                "NotNull"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        It "Returns the configured value for a known setting" {
            $result = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [int]
        }

        It "Returns the fallback value when config does not exist" {
            $result = Get-DbatoolsConfigValue -FullName "dbatoolsci.nonexistent.setting" -Fallback 42
            $result | Should -Be 42
        }

        It "Returns null when config does not exist and no fallback" {
            $result = Get-DbatoolsConfigValue -FullName "dbatoolsci.nonexistent.setting"
            $result | Should -BeNullOrEmpty
        }
    }
}