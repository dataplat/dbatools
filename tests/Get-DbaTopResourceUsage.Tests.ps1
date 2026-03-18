#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTopResourceUsage",
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
                "Database",
                "ExcludeDatabase",
                "Type",
                "Limit",
                "EnableException",
                "ExcludeSystem"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $splatDuration = @{
            SqlInstance = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            Type        = "Duration"
            Database    = "master"
        }
        $results = Get-DbaTopResourceUsage @splatDuration

        $splatExcluded = @{
            SqlInstance     = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            Type            = "Duration"
            ExcludeDatabase = "master"
        }
        $resultsExcluded = Get-DbaTopResourceUsage @splatExcluded
    }

    Context "Command returns proper info" {
        It "returns results" {
            $results.Count -gt 0 | Should -Be $true
        }

        It "only returns results from master" {
            foreach ($result in $results) {
                $result.Database | Should -Be "master"
            }
        }

        # Each of the 4 -Types return slightly different information so this way, we can check to ensure only duration was returned
        It "Should have correct properties for Duration" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ObjectName",
                "QueryHash",
                "TotalElapsedTimeMs",
                "ExecutionCount",
                "AverageDurationMs",
                "QueryTotalElapsedTimeMs",
                "QueryText"
            )
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "No results for excluded database" {
            $resultsExcluded.Database -notcontains "master" | Should -Be $true
        }
    }
}