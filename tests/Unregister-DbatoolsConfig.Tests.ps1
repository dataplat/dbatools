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
                "Scope",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-049). Real registry/file unregistration cannot be asserted
    # under this harness - Invoke-ManualPester blanks the module-scope $script:path_Registry*/
    # $script:path_File* variables (RB-IMP-51, the W1-032 Register class), so the begin-block
    # store collection reads empty stores here for the script function and the compiled
    # cmdlet alike. The out-of-harness registry round-trip is pinned by the migration smoke
    # battery (see the W1-041 tracker Evidence). These tests pin the harness-observable
    # no-op shapes: no pipeline output, no warnings.

    Context "No-op paths" {
        It "Silently ignores an unregistered FullName" {
            $results = @(Unregister-DbatoolsConfig -FullName "dbatoolsci.doesnotexist$(Get-Random)" -WarningVariable warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            $results.Count | Should -BeExactly 0
            @($warn).Count | Should -BeExactly 0
        }

        It "Silently ignores a module filter that matches nothing" {
            $results = @(Unregister-DbatoolsConfig -Module "dbatoolscinomatch$(Get-Random)" -WarningVariable warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            $results.Count | Should -BeExactly 0
            @($warn).Count | Should -BeExactly 0
        }

        It "Silently ignores a piped configuration object" {
            $configName = "dbatoolsci.unregpipe$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "x"
            $results = @(Get-DbatoolsConfig -FullName $configName | Unregister-DbatoolsConfig -WarningVariable warn -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            $results.Count | Should -BeExactly 0
            @($warn).Count | Should -BeExactly 0
        }
    }
}