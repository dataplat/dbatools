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
    # by the UnitTests above. Two branches short-circuit BEFORE the window is ever built and are
    # safely automatable: (1) Windows Presentation Framework unavailable (begin(), non-Windows only);
    # (2) the connection failing (process catch, before any XAML/window creation - runnable on
    # Windows with a throwing connection mock, so it never reaches ShowDialog).
    Context "When Windows Presentation Framework is unavailable" -Skip:(-not ($IsLinux -or $IsMacOS)) {
        BeforeAll {
            # spy on the connection so we can prove the guard returns BEFORE connecting.
            $splatMock = @{
                CommandName = "Connect-DbaInstance"
                MockWith    = { }
                ModuleName  = "dbatools"
            }
            Mock @splatMock
        }

        It "Warns and returns nothing WITHOUT attempting a connection" {
            # On Linux/macOS the PresentationFramework assembly is not available, so the begin-block
            # Add-Type fails, Stop-Function sets the interrupt flag, and process returns before the
            # Connect-DbaInstance call. -SqlInstance is a throwaway value that is never reached.
            $splatGuard = @{
                SqlInstance     = "dbatoolsci_noconnect"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Show-DbaDbList @splatGuard)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1
            # dbatools Write-Message prefixes the warning with bracketed [timestamp]/[function]
            # metadata; strip those leading groups and compare the bare payload exactly.
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "Windows Presentation Framework required but not installed"
            # the guard short-circuits before any connection attempt
            $splatAssert = @{
                CommandName = "Connect-DbaInstance"
                Times       = 0
                Exactly     = $true
                Scope       = "It"
                ModuleName  = "dbatools"
            }
            Assert-MockCalled @splatAssert
        }
    }

    Context "When the instance cannot be connected" -Skip:($IsLinux -or $IsMacOS) {
        BeforeAll {
            # a throwing connection mock drives the process-block catch, which Stop-Functions and
            # returns before any window is built - so ShowDialog() is never reached on Windows.
            $splatMockThrow = @{
                CommandName = "Connect-DbaInstance"
                MockWith    = { throw "mocked connection failure" }
                ModuleName  = "dbatools"
            }
            Mock @splatMockThrow
        }

        It "Warns and returns nothing without opening the dialog" {
            $splatConn = @{
                SqlInstance     = "dbatoolsci_noconnect"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = @(Show-DbaDbList @splatConn)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1
            # the catch calls Stop-Function -Message "Failure" -ErrorRecord $_, and Write-Message's
            # _errorQualifiedMessage renders that as "Failure | <exception message>". Strip the
            # bracketed metadata prefix and compare the exact payload.
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "Failure | mocked connection failure"
            $splatAssertConn = @{
                CommandName = "Connect-DbaInstance"
                Times       = 1
                Exactly     = $true
                Scope       = "It"
                ModuleName  = "dbatools"
            }
            Assert-MockCalled @splatAssertConn
        }
    }
}