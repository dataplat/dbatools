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
                "NetsendLevel",
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

        # Use pipeline removal -- Remove-DbaAgentJob -SqlInstance has a variable optimization
        # bug in the PS1 that prevents direct -SqlInstance usage in child scopes.
        Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -ErrorAction SilentlyContinue |
            Remove-DbaAgentJob -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "New Agent Job is added properly" {
        It "Should have the right name and description" {
            $results = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Description $jobDescription -OutVariable "global:dbatoolsciOutput"
            $results.Name | Should -Be $jobName
            $results.Description | Should -Be $jobDescription
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
            $newresults.Name | Should -Be $jobName
            $newresults.Description | Should -Be $jobDescription
        }

        It "Should not write over existing jobs" {
            # C# cmdlet routes StopFunction warnings through InvokeCommand.InvokeScript(),
            # which bypasses -WarningVariable capture. Use 3>&1 redirection to capture
            # the warning stream directly.
            $warnings = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Description $jobDescription -WarningAction Continue 3>&1 |
                Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] }
            ($warnings.Message -match "already exists").Count | Should -BeGreaterThan 0
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct output type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.Job]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Category",
                "OwnerLoginName",
                "CurrentRunStatus",
                "CurrentRunRetryAttempt",
                "Enabled",
                "LastRunDate",
                "LastRunOutcome",
                "HasSchedule",
                "OperatorToEmail",
                "CreateDate"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $typeNames = @($help.returnValues.returnValue.type.name)
            ($typeNames -match "Microsoft\.SqlServer\.Management\.Smo\.Agent\.Job").Count | Should -BeGreaterThan 0
        }
    }
}