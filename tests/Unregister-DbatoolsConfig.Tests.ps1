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

    Context "Harness-observable failure shape (RB-IMP-51 blanked store paths)" {
        It "FullName input dies on the blanked registry path" {
            { Unregister-DbatoolsConfig -FullName "dbatoolsci.doesnotexist$(Get-Random)" } | Should -Throw -ExpectedMessage "*Cannot bind argument to parameter*"
        }

        It "Module input dies on the blanked registry path" {
            { Unregister-DbatoolsConfig -Module "dbatoolscinomatch$(Get-Random)" } | Should -Throw -ExpectedMessage "*Cannot bind argument to parameter*"
        }

        It "Piped configuration input dies on the blanked registry path" {
            $configName = "dbatoolsci.unregpipe$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "x"
            { Get-DbatoolsConfig -FullName $configName | Unregister-DbatoolsConfig } | Should -Throw -ExpectedMessage "*Cannot bind argument to parameter*"
        }
    }
}