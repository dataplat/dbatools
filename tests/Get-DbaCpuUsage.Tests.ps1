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
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaCpuUsage -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.Management.Infrastructure.CimInstance]
            $result.CimClass.CimClassName | Should -Be "Win32_PerfFormattedData_PerfProc_Thread"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'ContextSwitchesPersec',
                'ElapsedTime',
                'IDProcess',
                'Spid',
                'PercentPrivilegedTime',
                'PercentProcessorTime',
                'PercentUserTime',
                'PriorityBase',
                'PriorityCurrent',
                'StartAddress',
                'ThreadStateValue',
                'ThreadWaitReasonValue',
                'Process',
                'Query'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has dbatools-added properties" {
            $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result[0].PSObject.Properties.Name | Should -Contain 'InstanceName'
            $result[0].PSObject.Properties.Name | Should -Contain 'SqlInstance'
            $result[0].PSObject.Properties.Name | Should -Contain 'Spid'
            $result[0].PSObject.Properties.Name | Should -Contain 'Process'
            $result[0].PSObject.Properties.Name | Should -Contain 'Query'
            $result[0].PSObject.Properties.Name | Should -Contain 'ThreadStateValue'
            $result[0].PSObject.Properties.Name | Should -Contain 'ThreadWaitReasonValue'
        }
    }

    Context "Output with -Threshold parameter" {
        BeforeAll {
            $result = Get-DbaCpuUsage -SqlInstance $TestConfig.InstanceSingle -Threshold 10 -EnableException
        }

        It "Filters to threads with CPU usage at or above threshold" {
            # May return empty if no threads meet threshold, which is valid
            if ($result) {
                $result[0].PercentProcessorTime | Should -BeGreaterOrEqual 10
            }
        }

        It "Returns same output type and properties when threshold is used" {
            if ($result) {
                $result | Should -BeOfType [Microsoft.Management.Infrastructure.CimInstance]
                $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
                $result[0].PSObject.Properties.Name | Should -Contain 'PercentProcessorTime'
            }
        }
    }
}