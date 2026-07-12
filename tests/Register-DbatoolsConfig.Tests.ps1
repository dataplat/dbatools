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
    # Characterization tests (TA-038): registration targets the user-default registry
    # scope on Windows - local machine state only, no SQL instance needed.

    Context "Registry-based registration" {
        BeforeAll {
            $configSuffix = Get-Random
            $configName = "dbatoolsci.registertest$configSuffix"
            $null = Set-DbatoolsConfig -FullName $configName -Value "regvalue$configSuffix" -PassThru
            $dbatoolsModule = Get-Module dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
            $registryPath = & $dbatoolsModule { $script:path_RegistryUserDefault }
        }

        AfterAll {
            Unregister-DbatoolsConfig -FullName "dbatoolsci.registertest$configSuffix" -ErrorAction SilentlyContinue
        }

        It "Registers a value by FullName to the user default registry scope" {
            Register-DbatoolsConfig -FullName $configName
            (Get-ItemProperty -Path $registryPath -Name $configName).$configName | Should -Match "regvalue$configSuffix"
        }

        It "Registers by module and name" {
            Unregister-DbatoolsConfig -FullName $configName
            Register-DbatoolsConfig -Module dbatoolsci -Name "registertest$configSuffix"
            (Get-ItemProperty -Path $registryPath -Name $configName).$configName | Should -Match "regvalue$configSuffix"
        }

        It "Accepts Config objects from the pipeline" {
            Unregister-DbatoolsConfig -FullName $configName
            Get-DbatoolsConfig -FullName $configName | Register-DbatoolsConfig
            (Get-ItemProperty -Path $registryPath -Name $configName).$configName | Should -Match "regvalue$configSuffix"
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>