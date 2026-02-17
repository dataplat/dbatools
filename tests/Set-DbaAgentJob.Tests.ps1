#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentJob",
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
                "NewName",
                "Enabled",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $jobName = "dbatoolsci_setjob_$(Get-Random)"
        $splatNewJob = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = $jobName
            Description = "Initial description"
        }
        $null = New-DbaAgentJob @splatNewJob

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When modifying agent job properties" {
        It "Changes job description" {
            $splatSetJob = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                Description = "Updated description"
            }
            $results = Set-DbaAgentJob @splatSetJob -OutVariable "global:dbatoolsciOutput"
            $results.Description | Should -Be "Updated description"
        }

        It "Changes job to disabled" {
            $results = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Disabled
            $results.IsEnabled | Should -BeFalse
        }

        It "Changes job to enabled" {
            $results = Set-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName -Enabled
            $results.IsEnabled | Should -BeTrue
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
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
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Agent\.Job"
        }
    }
}