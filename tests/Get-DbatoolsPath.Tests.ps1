#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Name",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (W1-017): pure config-store compute over Path.Managed.* keys.
    BeforeAll {
        $managedPathName = "dbatoolsci$(Get-Random)"
        $null = Set-DbatoolsConfig -FullName "Path.Managed.$managedPathName" -Value "C:\temp\dbatoolsci"
    }

    Context "Managed path retrieval" {
        It "returns the configured managed path" {
            Get-DbatoolsPath -Name $managedPathName | Should -Be "C:\temp\dbatoolsci"
        }

        It "binds the name positionally" {
            Get-DbatoolsPath $managedPathName | Should -Be "C:\temp\dbatoolsci"
        }

        It "returns null-shaped nothing for an unknown managed path" {
            $result = Get-DbatoolsPath -Name "no.such.managed.path.$(Get-Random)"
            $null -eq $result | Should -Be $true
        }
    }
}