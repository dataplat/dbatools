#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPfDataCollectorCounterSample",
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
                "CollectorSet",
                "Collector",
                "Counter",
                "Continuous",
                "ListSet",
                "MaxSamples",
                "SampleInterval",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying command works" {
        It "returns a result with the right computername and name is not null" {
            $results = Get-DbaPfDataCollectorCounterSample | Select-Object -First 1
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaPfDataCollectorCounterSample -EnableException | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "DataCollectorSet",
                "DataCollector",
                "Name",
                "Timestamp",
                "Path",
                "InstanceName",
                "CookedValue",
                "RawValue",
                "SecondValue",
                "MultipleCount",
                "CounterType",
                "SampleTimestamp",
                "SampleTimestamp100NSec",
                "Status",
                "DefaultScale",
                "TimeBase"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Excludes Sample and CounterSampleObject from default view" {
            $defaultProps = ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
            $defaultProps | Should -Not -Contain "Sample"
            $defaultProps | Should -Not -Contain "CounterSampleObject"
        }
    }
}