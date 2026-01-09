#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaNetworkLatency",
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
                "Query",
                "Count",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns proper info" {
        BeforeAll {
            $pipelineResults = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Test-DbaNetworkLatency -EnableException
            $parameterResults = Test-DbaNetworkLatency -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -EnableException
        }

        It "returns two objects when using pipeline" {
            $pipelineResults.Count | Should -Be 2
        }

        It "executes 3 times by default" {
            $parameterResults.ExecutionCount | Should -Be 3, 3
        }

        It "has the correct properties" {
            $result = $parameterResults | Select-Object -First 1
            $expectedPropsDefault = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ExecutionCount",
                "Total",
                "Average",
                "ExecuteOnlyTotal",
                "ExecuteOnlyAverage",
                "NetworkOnlyTotal"
            )
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedPropsDefault | Sort-Object)
        }
    }
}