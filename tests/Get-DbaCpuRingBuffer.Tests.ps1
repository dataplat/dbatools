#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaCpuRingBuffer",
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
                "CollectionMinutes",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because non-useful info from newly started sql servers.

    Context "When retrieving CPU ring buffer data" {
        BeforeAll {
            $results = @(Get-DbaCpuRingBuffer -SqlInstance $TestConfig.InstanceSingle -CollectionMinutes 100)
        }

        It "Returns CPU performance metrics from ring buffer" {
            $results.Count | Should -BeGreaterThan 0
        }

        It "Returns output with expected properties" {
            $results | Should -Not -BeNullOrEmpty
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "RecordId",
                "EventTime",
                "SQLProcessUtilization",
                "OtherProcessUtilization",
                "SystemIdle"
            )
            foreach ($prop in $expectedProperties) {
                $results[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}