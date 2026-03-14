#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaInstantFileInitialization",
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
    Context "Gets IFI status" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $results = Test-DbaInstantFileInitialization -ComputerName $TestConfig.ComputerName
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Results have expected properties" {
            $results[0].ComputerName | Should -Not -BeNullOrEmpty
            $results[0].ServiceName | Should -Not -BeNullOrEmpty
            $results[0].IsEnabled | Should -BeOfType [bool]
            $results[0].IsBestPractice | Should -BeOfType [bool]
        }
    }
}
