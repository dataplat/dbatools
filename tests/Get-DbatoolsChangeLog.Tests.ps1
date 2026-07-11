#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsChangeLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Local",
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
    # Characterization tests (W1-012): only the -Local branch is CI-safe - the default branch
    # launches the system browser via Start-Process, which is exercised by the migration smoke
    # battery on the lab workstation instead.
    Context "Local changelog fallback" {
        It "warns that the changelog is only available online" {
            $null = Get-DbatoolsChangeLog -Local -WarningVariable warn 3>$null
            $warn | Should -Match "changelog is only available online"
        }

        It "returns no output for the Local branch" {
            $results = @(Get-DbatoolsChangeLog -Local 3>$null)
            $results.Count | Should -Be 0
        }

        It "still warns rather than throws under EnableException" {
            # Write-Message warnings are not Stop-Function failures: EnableException must not
            # turn the deprecation warning into a terminating error.
            $null = Get-DbatoolsChangeLog -Local -EnableException -WarningVariable warn 3>$null
            $warn | Should -Match "changelog is only available online"
        }
    }
}