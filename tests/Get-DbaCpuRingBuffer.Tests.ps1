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
        It "Returns CPU performance metrics from ring buffer" {
            $results = @(Get-DbaCpuRingBuffer -SqlInstance $TestConfig.InstanceSingle -CollectionMinutes 100)
            $results.Count | Should -BeGreaterThan 0
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaCpuRingBuffer -SqlInstance $TestConfig.InstanceSingle -CollectionMinutes 60 -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "RecordId",
                "EventTime",
                "SQLProcessUtilization",
                "OtherProcessUtilization",
                "SystemIdle"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}