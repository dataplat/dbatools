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

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaWaitStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100 -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "WaitType",
                "Category",
                "WaitSeconds",
                "ResourceSeconds",
                "SignalSeconds",
                "WaitCount",
                "Percentage",
                "AverageWaitSeconds",
                "AverageResourceSeconds",
                "AverageSignalSeconds",
                "URL"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Does not include Notes and Ignorable properties by default" {
            $actualProps = $result[0].PSObject.Properties.Name
            $actualProps | Should -Not -Contain "Notes" -Because "Notes is excluded by default"
            $actualProps | Should -Not -Contain "Ignorable" -Because "Ignorable is excluded by default"
        }
    }

    Context "Output with -IncludeIgnorable" {
        BeforeAll {
            $result = Get-DbaWaitStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100 -IncludeIgnorable -EnableException
        }

        It "Includes Ignorable property when -IncludeIgnorable is specified" {
            $result[0].PSObject.Properties.Name | Should -Contain "Ignorable" -Because "-IncludeIgnorable adds the Ignorable property"
        }

        It "Does not include Notes property even with -IncludeIgnorable" {
            $result[0].PSObject.Properties.Name | Should -Not -Contain "Notes" -Because "Notes is always excluded from default display"
        }
    }
}