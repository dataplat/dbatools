#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentJob",
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
                "Job",
                "Schedule",
                "ScheduleId",
                "Disabled",
                "Description",
                "StartStepId",
                "Category",
                "OwnerLogin",
                "EventLogLevel",
                "EmailLevel",
                "PageLevel",
                "EmailOperator",
                "NetsendOperator",
                "PageOperator",
                "DeleteLevel",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Create unique job names for this test run to avoid conflicts
        $jobName = "dbatoolsci_job_$(Get-Random)"
        $jobDescription = "Test job created by dbatools unit tests"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup and ignore all output
        Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "New Agent Job is added properly" {
        It "Should have the right name and description" {
            $results = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName -Description $jobDescription
            $results.Name | Should -Be $jobName
            $results.Description | Should -Be $jobDescription
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName
            $newresults.Name | Should -Be $jobName
            $newresults.Description | Should -Be $jobDescription
        }

        It "Should not write over existing jobs" {
            $results = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName -Description $jobDescription -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "already exists" | Should -Be $true
        }
    }
}