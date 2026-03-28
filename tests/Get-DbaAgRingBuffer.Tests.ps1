#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgRingBuffer",
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
                "RingBufferType",
                "CollectionMinutes",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When retrieving HADR ring buffer data" {
        It "Returns results with expected properties" {
            $results = @(Get-DbaAgRingBuffer -SqlInstance $TestConfig.InstanceSingle)
            if ($results.Count -gt 0) {
                $results[0].PSObject.Properties.Name | Should -Contain "ComputerName"
                $results[0].PSObject.Properties.Name | Should -Contain "InstanceName"
                $results[0].PSObject.Properties.Name | Should -Contain "SqlInstance"
                $results[0].PSObject.Properties.Name | Should -Contain "RingBufferType"
                $results[0].PSObject.Properties.Name | Should -Contain "RecordId"
                $results[0].PSObject.Properties.Name | Should -Contain "EventTime"
                $results[0].PSObject.Properties.Name | Should -Contain "Record"
            }
        }

        It "Filters by RingBufferType when specified" {
            $results = @(Get-DbaAgRingBuffer -SqlInstance $TestConfig.InstanceSingle -RingBufferType RING_BUFFER_HADRDBMGR_API)
            foreach ($result in $results) {
                $result.RingBufferType | Should -Be "RING_BUFFER_HADRDBMGR_API"
            }
        }
    }
}
