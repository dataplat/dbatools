#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRgWorkloadGroup",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When retrieving workload groups" {
        It "Returns the built-in default workload group with decorations" {
            $results = @(Get-DbaRgWorkloadGroup -SqlInstance $TestConfig.InstanceSingle)
            $results | Should -Not -BeNullOrEmpty
            $defaultGroup = @($results | Where-Object Name -eq "default")
            $defaultGroup | Should -Not -BeNullOrEmpty
            $defaultGroup[0].ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Accepts resource pools from the pipeline" {
            $results = @(Get-DbaResourceGovernor -SqlInstance $TestConfig.InstanceSingle | Get-DbaRgResourcePool | Get-DbaRgWorkloadGroup)
            $results | Should -Not -BeNullOrEmpty
        }
    }
}