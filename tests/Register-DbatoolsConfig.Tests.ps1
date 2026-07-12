#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Register-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Config",
                "FullName",
                "Module",
                "Name",
                "Scope",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-038). NOTE: real registry/file registration cannot be
    # asserted under this harness - Invoke-ManualPester blanks the module-scope
    # $script:path_Registry*/$script:path_File* variables (RB-IMP-51), so the command's own
    # write targets are empty here for the script function and the compiled cmdlet alike.
    # (A 2026-07-12 revision asserted a real HKCU round-trip here after gate runs appeared
    # to show the cmdlet registering under the harness - those runs were measuring a Gallery
    # dbatools 2.8.2 function through the Gallery-shadow auto-load incident, see
    # migration/CAMPAIGN-STATE.md. Post-fix, the compiled cmdlet's module hop reads the same
    # blanked variables, so the honest harness shape below is restored.)
    # The out-of-harness registry/file behavior is pinned by the migration smoke battery
    # (see migration/trackers WAVE-1 W1-032 Evidence). These tests pin the
    # environment-independent no-op paths plus the harness-observable failure shape.

    Context "No-op paths" {
        It "Silently ignores an unknown FullName" {
            $results = @(Register-DbatoolsConfig -FullName "dbatoolsci.doesnotexist$(Get-Random)" -WarningVariable warn -WarningAction SilentlyContinue)
            $results.Count | Should -BeExactly 0
            @($warn).Count | Should -BeExactly 0
        }

        It "Silently ignores a module filter that matches nothing" {
            $results = @(Register-DbatoolsConfig -Module "dbatoolscinomatch$(Get-Random)" -WarningVariable warn -WarningAction SilentlyContinue)
            $results.Count | Should -BeExactly 0
            @($warn).Count | Should -BeExactly 0
        }
    }

    Context "Registration under the harness" {
        It "Warns Failed-to-export when the module path variables are blanked (RB-IMP-51 harness reality)" {
            $configName = "dbatoolsci.registertest$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "regvalue"
            $null = Register-DbatoolsConfig -FullName $configName -WarningVariable warn -WarningAction SilentlyContinue
            $warn | Should -Match "Failed to export"
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>