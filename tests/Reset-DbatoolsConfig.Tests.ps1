#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Reset-DbatoolsConfig",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-042). Pure config-store scenarios, CI-safe and harness-safe:
    # the command only touches ConfigurationHost statics (per-process), never registry/files.
    # Behavior pinned live against the script function on both editions 2026-07-12: reset
    # restores the -Initialize-time default; an uninitialized item warns "Failed to reset the
    # configuration item." with the inner "Object has not been initialized yet and thus has no
    # state to revert to" and keeps its value (throws that inner message under
    # -EnableException); pipeline Config input resets without warnings (the function's
    # case-sensitive -ceq type-name filter absorbs the double bind to -FullName); -WhatIf is a
    # no-op; the command emits nothing to the pipeline.

    Context "Reset by FullName" {
        It "Restores the initialize-time default and emits nothing" {
            $configName = "dbatoolscireset.fullname$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "orig" -Initialize -Validation string
            $null = Set-DbatoolsConfig -FullName $configName -Value "changed"
            $results = Reset-DbatoolsConfig -FullName $configName
            @($results).Count | Should -BeExactly 0
            Get-DbatoolsConfigValue -FullName $configName | Should -BeExactly "orig"
        }
    }

    Context "Reset by Module and Name" {
        It "Resets only the matching items in the module" {
            $moduleName = "dbatoolscireset$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName "$moduleName.m1" -Value "a" -Initialize -Validation string
            $null = Set-DbatoolsConfig -FullName "$moduleName.m2" -Value "b" -Initialize -Validation string
            $null = Set-DbatoolsConfig -FullName "$moduleName.m1" -Value "x"
            $null = Set-DbatoolsConfig -FullName "$moduleName.m2" -Value "y"
            Reset-DbatoolsConfig -Module $moduleName -Name "m*"
            Get-DbatoolsConfigValue -FullName "$moduleName.m1" | Should -BeExactly "a"
            Get-DbatoolsConfigValue -FullName "$moduleName.m2" | Should -BeExactly "b"
        }
    }

    Context "Pipeline input" {
        It "Resets a piped configuration object without warnings" {
            $configName = "dbatoolscireset.pipe$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "orig" -Initialize -Validation string
            $null = Set-DbatoolsConfig -FullName $configName -Value "changed"
            $merged = Get-DbatoolsConfig -FullName $configName | Reset-DbatoolsConfig 3>&1
            @($merged).Count | Should -BeExactly 0
            Get-DbatoolsConfigValue -FullName $configName | Should -BeExactly "orig"
        }
    }

    Context "Uninitialized item" {
        It "Warns and keeps the value" {
            $configName = "dbatoolscireset.uninit$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "keepme"
            $merged = Reset-DbatoolsConfig -FullName $configName 3>&1
            $failureWarnings = @($merged) -match "Failed to reset the configuration item"
            $failureWarnings | Should -Not -BeNullOrEmpty
            Get-DbatoolsConfigValue -FullName $configName | Should -BeExactly "keepme"
        }

        It "Throws the inner message under EnableException" {
            $configName = "dbatoolscireset.uninitee$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "keepme"
            { Reset-DbatoolsConfig -FullName $configName -EnableException } | Should -Throw -ExpectedMessage "*has not been initialized yet*"
        }
    }

    Context "WhatIf" {
        It "Changes nothing" {
            $configName = "dbatoolscireset.whatif$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "orig" -Initialize -Validation string
            $null = Set-DbatoolsConfig -FullName $configName -Value "changed"
            Reset-DbatoolsConfig -FullName $configName -WhatIf
            Get-DbatoolsConfigValue -FullName $configName | Should -BeExactly "changed"
        }
    }
}