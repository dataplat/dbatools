#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Show-DbaDbList",
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
                "Title",
                "Header",
                "DefaultDb",
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
    # NOTE ON COVERAGE: Show-DbaDbList's core behavior is an INTERACTIVE WPF dialog - it builds a
    # window and calls $window.ShowDialog(), which blocks for user input and requires an interactive
    # desktop session, then returns the selected database name (or $null on cancel). That leg cannot
    # be exercised in a headless/non-interactive test harness (it would block indefinitely and needs
    # a window station), so it is DEFERRED to manual verification; the parameter contract is covered
    # by the UnitTests above. The one branch that IS safely automatable is the graceful degradation
    # when Windows Presentation Framework is unavailable, which the command checks in begin() BEFORE
    # any connection - so it needs no live instance and runs on non-Windows only.
    Context "When Windows Presentation Framework is unavailable" -Skip:(-not ($IsLinux -or $IsMacOS)) {
        It "Warns and returns nothing instead of attempting the dialog" {
            # On Linux/macOS the PresentationFramework assembly is not available, so the begin-block
            # Add-Type fails and the command Stop-Functions before connecting. -SqlInstance is a
            # throwaway value - the guard fires first, so no connection is attempted.
            $splatGuard = @{
                SqlInstance     = "dbatoolsci_noconnect"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Show-DbaDbList @splatGuard
            $result | Should -BeNullOrEmpty
            $warn -join " " | Should -Match "Windows Presentation Framework required but not installed"
        }
    }
}