#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaProductKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting product key for local computer" {
        BeforeAll {
            $results = Get-DbaProductKey -ComputerName $env:ComputerName
        }

        It "Should return results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Version property populated" {
            $results[0].Version | Should -Not -BeNullOrEmpty
        }

        It "Should have Edition property populated" {
            $results[0].Edition | Should -Not -BeNullOrEmpty
        }

        It "Should have Key property populated" {
            $results[0].Key | Should -Not -BeNullOrEmpty
        }
    }
}