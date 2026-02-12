#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaCpuUsage",
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
                "Credential",
                "Threshold",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets the CPU Usage" {
        It "Results are not empty" {
            $results = Get-DbaCpuUsage -SqlInstance $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }

        It "Returns output with expected properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].psobject.Properties.Name | Should -Contain "ComputerName"
            $results[0].psobject.Properties.Name | Should -Contain "SqlInstance"
            $results[0].psobject.Properties.Name | Should -Contain "Spid"
        }

        It "Has the expected default display properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "ContextSwitchesPersec",
                "ElapsedTime",
                "IDProcess",
                "Spid",
                "PercentPrivilegedTime",
                "PercentProcessorTime",
                "PercentUserTime",
                "PriorityBase",
                "PriorityCurrent",
                "StartAddress",
                "ThreadStateValue",
                "ThreadWaitReasonValue",
                "Process",
                "Query"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}