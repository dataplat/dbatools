#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "ModuleName",
                "ModuleVersion",
                "Scope",
                "IncludeFilter",
                "ExcludeFilter",
                "Peek",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $configPath = "$($TestConfig.Temp)\dbatoolsci_config_$(Get-Random).json"
            $null = Get-DbatoolsConfig -Module message | Export-DbatoolsConfig -OutPath $configPath
        }

        AfterAll {
            Remove-Item -Path $configPath -ErrorAction SilentlyContinue
        }

        It "Returns no output when importing without -Peek" {
            $outputResult = Import-DbatoolsConfig -Path $configPath
            $outputResult | Should -BeNullOrEmpty
        }

        It "Returns configuration elements when using -Peek" {
            $peekResult = Import-DbatoolsConfig -Path $configPath -Peek
            $peekResult | Should -Not -BeNullOrEmpty
            $peekResult[0].FullName | Should -Not -BeNullOrEmpty
        }

        It "Returns elements with expected properties when using -Peek" {
            $peekResult = Import-DbatoolsConfig -Path $configPath -Peek
            $peekResult[0].psobject.Properties.Name | Should -Contain "FullName"
            $peekResult[0].psobject.Properties.Name | Should -Contain "Value"
            $peekResult[0].psobject.Properties.Name | Should -Contain "Type"
            $peekResult[0].psobject.Properties.Name | Should -Contain "KeepPersisted"
        }
    }
}