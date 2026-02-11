#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWaitStatistic",
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
                "Threshold",
                "IncludeIgnorable",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaWaitStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100
        }

        It "returns results" {
            $results.Count -gt 0 | Should -Be $true
        }

        It "returns a hyperlink for each result" {
            foreach ($result in $results) {
                $result.URL -match "sqlskills.com" | Should -Be $true
            }
        }
    }

    Context "Command returns proper info when using parameter IncludeIgnorable" {
        BeforeAll {
            $ignoredWaits = @(
                "REQUEST_FOR_DEADLOCK_SEARCH",
                "SLEEP_MASTERDBREADY",
                "SLEEP_TASK",
                "LAZYWRITER_SLEEP"
            )
            $results = Get-DbaWaitStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100 -IncludeIgnorable | Where-Object WaitType -in $ignoredWaits
        }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "results includes ignorable column" {
            $results[0].PSObject.Properties.Name.Contains("Ignorable") | Should -Be $true
        }

        It "returns a hyperlink for each result" {
            foreach ($result in $results) {
                $result.URL -match "sqlskills.com" | Should -Be $true
            }
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputResult = Get-DbaWaitStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100
        }

        It "Returns output of type PSCustomObject" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected default display properties" {
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "WaitType", "Category", "WaitSeconds", "ResourceSeconds", "SignalSeconds", "WaitCount", "Percentage", "AverageWaitSeconds", "AverageResourceSeconds", "AverageSignalSeconds", "URL")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Excludes Notes and Ignorable from default display without IncludeIgnorable" {
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "Notes" -Because "Notes should be excluded from default display"
            $defaultProps | Should -Not -Contain "Ignorable" -Because "Ignorable should be excluded from default display without IncludeIgnorable"
        }

        It "Includes Ignorable in default display with IncludeIgnorable" {
            $outputWithIgnorable = Get-DbaWaitStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100 -IncludeIgnorable
            $defaultProps = $outputWithIgnorable[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Contain "Ignorable" -Because "Ignorable should be in the default display set when IncludeIgnorable is specified"
            $defaultProps | Should -Not -Contain "Notes" -Because "Notes should still be excluded from default display"
        }
    }
}