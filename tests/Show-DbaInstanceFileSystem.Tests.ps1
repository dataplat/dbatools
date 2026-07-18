#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Show-DbaInstanceFileSystem",
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
    # Characterization context (W1-094 law: an empty run is never green). The command opens a
    # WPF tree view on success, so the only headless-safe characterization is the pre-GUI
    # failure path: an unresolvable instance warns and emits nothing (no window ever opens).
    Context "When the instance cannot be reached" {
        It "Warns and returns nothing without opening the GUI" {
            $showResults = Show-DbaInstanceFileSystem -SqlInstance "dbatoolsci-nohost-$(Get-Random)" -WarningAction SilentlyContinue -WarningVariable showWarning
            $showResults | Should -BeNullOrEmpty
            $showWarning | Should -Not -BeNullOrEmpty
        }
    }
}
