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

    Context "Multi-record pipe emits each workload group exactly once (deviation from source, #6 / DEF-012)" {
        # The retired function accumulated instances in a process-scope `$InputObject +=`, so a
        # multi-record pipe re-emitted earlier records' groups: record 2 relisted record 1's groups.
        # The compiled port runs each pipeline record in its own hop scope and emits every workload
        # group exactly once. This is the #6 ruling (a) deviation from source, and a single-instance
        # leg cannot observe it - it needs at least two piped records.
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $instanceOne = $TestConfig.InstanceMulti1
            $instanceTwo = $TestConfig.InstanceMulti2
            $pipedResults = @($instanceOne, $instanceTwo | Get-DbaRgWorkloadGroup)
            $expectedResults = @(Get-DbaRgWorkloadGroup -SqlInstance $instanceOne) + @(Get-DbaRgWorkloadGroup -SqlInstance $instanceTwo)
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "emits each instance's workload groups exactly once across a two-instance pipe" {
            $pipedResults.Count | Should -Be $expectedResults.Count
        }

        It "never re-emits an earlier record's workload group" {
            $duplicated = $pipedResults | Group-Object -Property SqlInstance, Name | Where-Object Count -gt 1
            $duplicated | Should -BeNullOrEmpty
        }
    }
}