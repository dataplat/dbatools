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
    # store collection hits Test-Path with a null path and the call dies on the nested
    # binding error for the script function and the compiled cmdlet alike (validated against
    # the function both editions). The out-of-harness registry round-trip is pinned by the
    # migration smoke battery (see the W1-041 tracker Evidence).

    # EDITION SPLIT (engine, not command): Test-Path $null THROWS the binding error on 5.1
    # but returns $false on 7+ (the PS 6.1 Test-Path null/empty change), so the blanked
    # begin block dies on Desktop and silently collects nothing on Core.

    Context "Harness-observable shape (RB-IMP-51 blanked store paths)" {
        It "FullName input: dies on 5.1, silent no-op on 7+" {
            if ($PSVersionTable.PSEdition -ne "Core") {
                { Unregister-DbatoolsConfig -FullName "dbatoolsci.doesnotexist$(Get-Random)" } | Should -Throw -ExpectedMessage "*Cannot bind argument to parameter*"
            } else {
                $results = @(Unregister-DbatoolsConfig -FullName "dbatoolsci.doesnotexist$(Get-Random)" -WarningVariable warn -WarningAction SilentlyContinue)
                $results.Count | Should -BeExactly 0
                @($warn).Count | Should -BeExactly 0
            }
        }

        It "Module input: dies on 5.1, silent no-op on 7+" {
            if ($PSVersionTable.PSEdition -ne "Core") {
                { Unregister-DbatoolsConfig -Module "dbatoolscinomatch$(Get-Random)" } | Should -Throw -ExpectedMessage "*Cannot bind argument to parameter*"
            } else {
                $results = @(Unregister-DbatoolsConfig -Module "dbatoolscinomatch$(Get-Random)" -WarningVariable warn -WarningAction SilentlyContinue)
                $results.Count | Should -BeExactly 0
                @($warn).Count | Should -BeExactly 0
            }
        }

        It "Piped configuration input: dies on 5.1, silent no-op on 7+" {
            $configName = "dbatoolsci.unregpipe$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "x"
            if ($PSVersionTable.PSEdition -ne "Core") {
                { Get-DbatoolsConfig -FullName $configName | Unregister-DbatoolsConfig } | Should -Throw -ExpectedMessage "*Cannot bind argument to parameter*"
            } else {
                $results = @(Get-DbatoolsConfig -FullName $configName | Unregister-DbatoolsConfig -WarningVariable warn -WarningAction SilentlyContinue)
                $results.Count | Should -BeExactly 0
                @($warn).Count | Should -BeExactly 0
            }
        }
    }
}