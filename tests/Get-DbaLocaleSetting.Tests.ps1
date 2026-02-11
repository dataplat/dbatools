#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaLocaleSetting",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets LocaleSettings" {
        It "Gets results" {
            $results = Get-DbaLocaleSetting -ComputerName $env:ComputerName
            $results | Should -Not -Be $null
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaLocaleSetting -ComputerName $env:ComputerName
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected ComputerName property" {
            $result[0].ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Has locale-related properties from the registry" {
            $propNames = $result[0].psobject.Properties.Name
            $propNames | Should -Contain "ComputerName"
            # Locale registry key should have at least a few standard properties
            $propNames.Count | Should -BeGreaterThan 1
        }
    }
}