#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaResourceGovernor",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When retrieving the resource governor" {
        It "Returns the decorated resource governor object" {
            $results = @(Get-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle)
            $results.Count | Should -BeExactly 1
            $results[0].ComputerName | Should -Not -BeNullOrEmpty
            $results[0].Enabled | Should -BeIn $true, $false
            $results[0].ResourcePools | Should -Not -BeNullOrEmpty
        }
    }
}