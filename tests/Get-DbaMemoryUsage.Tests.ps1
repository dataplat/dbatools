#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaMemoryUsage",
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
                "MemoryCounterRegex",
                "PlanCounterRegex",
                "BufferCounterRegex",
                "SSASCounterRegex",
                "SSISCounterRegex",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaMemoryUsage -ComputerName $TestConfig.InstanceSingle
            $resultsSimple = Get-DbaMemoryUsage -ComputerName $TestConfig.InstanceSingle
        }

        It "returns results" {
            $results.Count -gt 0 | Should -BeTrue
        }
        It "has the correct properties" {
            $result = $results[0]
            $ExpectedProps = "ComputerName", "SqlInstance", "CounterInstance", "Counter", "Pages", "Memory"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "returns results from simple call" {
            $resultsSimple.Count -gt 0 | Should -BeTrue
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaMemoryUsage -ComputerName $TestConfig.InstanceSingle
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @("ComputerName", "SqlInstance", "CounterInstance", "Counter", "Pages", "Memory")
            foreach ($prop in $expectedProps) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist"
            }
        }

        It "Has dbasize property for Memory" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].Memory | Should -BeOfType [dbasize]
        }
    }
}