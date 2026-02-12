#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPfDataCollectorCounter",
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
            $results = Get-DbaPfDataCollectorCounter | Select-Object -First 1
        }

        It "returns a result with the right computername and name is not null" {
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -Be $null
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaPfDataCollectorCounter | Select-Object -First 1
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "DataCollectorSet", "DataCollector", "Name", "FileName")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected excluded properties available" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $excludedProps = @("Credential", "CounterObject", "DataCollectorSetXml")
            foreach ($prop in $excludedProps) {
                $defaultProps | Should -Not -Contain $prop -Because "property '$prop' should be excluded from the default display set"
            }
        }
    }
}