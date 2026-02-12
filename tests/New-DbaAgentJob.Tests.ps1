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
        Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "New Agent Job is added properly" {
        It "Should have the right name and description" {
            $script:results = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Description $jobDescription
            $script:results.Name | Should -Be $jobName
            $script:results.Description | Should -Be $jobDescription
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
            $newresults.Name | Should -Be $jobName
            $newresults.Description | Should -Be $jobDescription
        }

        It "Should not write over existing jobs" {
            $results = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Description $jobDescription -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "already exists" | Should -Be $true
        }

        It "Returns output of the documented type" {
            $script:results | Should -Not -BeNullOrEmpty
            $script:results[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.Job"
        }

        It "Has the expected default display properties" {
            if (-not $script:results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $script:results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Name", "Category", "OwnerLoginName", "CurrentRunStatus", "CurrentRunRetryAttempt", "Enabled", "LastRunDate", "LastRunOutcome", "HasSchedule", "OperatorToEmail", "CreateDate")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            if (-not $script:results) { Set-ItResult -Skipped -Because "no result to validate" }
            $script:results[0].psobject.Properties["Enabled"] | Should -Not -BeNullOrEmpty
            $script:results[0].psobject.Properties["Enabled"].MemberType | Should -Be "AliasProperty"
            $script:results[0].psobject.Properties["CreateDate"] | Should -Not -BeNullOrEmpty
            $script:results[0].psobject.Properties["CreateDate"].MemberType | Should -Be "AliasProperty"
        }
    }
}