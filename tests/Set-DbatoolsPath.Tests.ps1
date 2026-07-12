#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbatoolsPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Name",
                "Path",
                "Register",
                "Scope",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-046). In-session config-store scenarios only, CI-safe and
    # harness-safe (the -Register branch writes registry through Register-DbatoolsConfig,
    # whose targets are RB-IMP-51-blanked under this harness - it is exercised by the
    # migration smoke battery out of harness instead).

    Context "Managed path round-trip" {
        It "Sets a managed path retrievable via Get-DbatoolsPath and emits nothing" {
            $pathName = "dbatoolscipath$(Get-Random)"
            $results = Set-DbatoolsPath -Name $pathName -Path "C:\temp"
            @($results).Count | Should -BeExactly 0
            Get-DbatoolsPath -Name $pathName | Should -BeExactly "C:\temp"
        }

        It "Overwrites an existing managed path" {
            $pathName = "dbatoolscipath$(Get-Random)"
            Set-DbatoolsPath -Name $pathName -Path "C:\temp"
            Set-DbatoolsPath -Name $pathName -Path "C:\windows"
            Get-DbatoolsPath -Name $pathName | Should -BeExactly "C:\windows"
        }
    }
}