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
        BeforeAll {
            $results = Get-DbaPfDataCollectorCounterSample -OutVariable "global:dbatoolsciOutput" | Select-Object -First 1
        }

        It "returns a result with the right computername and name is not null" {
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
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
                "TimeBase",
                "Sample",
                "CounterSampleObject"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}