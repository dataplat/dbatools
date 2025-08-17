#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaPowerPlan",
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
                "PowerPlan",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $null = Set-DbaPowerPlan -ComputerName $TestConfig.instance2 -PowerPlan "Balanced"
    }

    Context "Command actually works" {
        It "Should return result for the server" {
            $results = Test-DbaPowerPlan -ComputerName $TestConfig.instance2
            $results | Should -Not -BeNullOrEmpty
            $results.ActivePowerPlan | Should -Be "Balanced"
            $results.RecommendedPowerPlan | Should -Be "High performance"
            $results.RecommendedInstanceId | Should -Be "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
            $results.IsBestPractice | Should -Be $false
        }

        It "Use Balanced plan as best practice" {
            $results = Test-DbaPowerPlan -ComputerName $TestConfig.instance2 -PowerPlan "Balanced"
            $results.IsBestPractice | Should -Be $true
        }
    }
}