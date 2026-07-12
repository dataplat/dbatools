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
        It "DIAG harness registration shape" {
            $configName = "dbatoolsci.registertest$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "regvalue"
            $err = @()
            try {
                $out = @(Register-DbatoolsConfig -FullName $configName -WarningVariable warn -WarningAction SilentlyContinue -ErrorVariable err -ErrorAction SilentlyContinue)
                $caught = "<none>"
            } catch {
                $caught = $PSItem.Exception.GetType().FullName + ":" + $PSItem.Exception.Message
            }
            $warnText = @($warn) -join "~"
            $errText = @($err | ForEach-Object { $PSItem.Exception.GetType().Name }) -join "~"
            $regPath = "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Default"
            $prop = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).PSObject.Properties[$configName]
            $regValue = if ($prop) { $prop.Value } else { "<missing>" }
            Remove-ItemProperty -Path $regPath -Name $configName -ErrorAction SilentlyContinue
            "warnN=$(@($warn).Count) warn=<$warnText> errN=$(@($err).Count) err=<$errText> caught=<$caught> outN=$($out.Count) reg=<$regValue>" | Should -BeExactly "IMPOSSIBLE"
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>