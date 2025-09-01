#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaProductKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip {
    # Skip IntegrationTests on AppVeyor because they fail for unknown reasons.

    Context "Gets ProductKey for Instances on $($env:ComputerName)" {
        BeforeAll {
            $results = Get-DbaProductKey -ComputerName $env:ComputerName
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Version for each result" {
            foreach ($row in $results) {
                $row.Version | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have Edition for each result" {
            foreach ($row in $results) {
                $row.Edition | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have Key for each result" {
            foreach ($row in $results) {
                $row.Key | Should -Not -BeNullOrEmpty
            }
        }
    }
}