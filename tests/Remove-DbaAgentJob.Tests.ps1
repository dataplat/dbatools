#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentJob",
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
                "KeepHistory",
                "KeepUnusedSchedule",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command removes jobs" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = New-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule dbatoolsci_daily -FrequencyType Daily -FrequencyInterval Everyday -Force
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob -Schedule dbatoolsci_daily
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command "select 1"
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if (Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule dbatoolsci_daily) {
                Remove-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule dbatoolsci_daily
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have deleted job: dbatoolsci_testjob" {
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob) | Should -BeNullOrEmpty
        }

        It "Should have deleted schedule: dbatoolsci_daily" {
            (Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule dbatoolsci_daily) | Should -BeNullOrEmpty
        }

        It "Should have deleted history: dbatoolsci_daily" {
            (Get-DbaAgentJobHistory -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob) | Should -BeNullOrEmpty
        }
    }

    Context "Command removes job but not schedule" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = New-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule dbatoolsci_weekly -FrequencyType Weekly -FrequencyInterval Everyday -Force
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_schedule -Schedule dbatoolsci_weekly
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_schedule -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command "select 1"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_schedule -KeepUnusedSchedule
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if (Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule dbatoolsci_weekly) {
                Remove-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule dbatoolsci_weekly
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have deleted job: dbatoolsci_testjob_schedule" {
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_schedule) | Should -BeNullOrEmpty
        }

        It "Should not have deleted schedule: dbatoolsci_weekly" {
            (Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule dbatoolsci_weekly) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command removes job but not history and supports piping" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $jobId = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_history | Select-Object -ExpandProperty JobId
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_history -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command "select 1"
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_history
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server.Query("delete from sysjobhistory where job_id = '$jobId'", "msdb")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have deleted job: dbatoolsci_testjob_history" {
            $null = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_history | Remove-DbaAgentJob -KeepHistory
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_history) | Should -BeNullOrEmpty
        }

        It -Skip:$true "Should not have deleted history: dbatoolsci_testjob_history" {
            ($server.Query("select 1 from sysjobhistory where job_id = '$jobId'", "msdb")) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command validates null/empty Job parameter" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_validation
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            if (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_validation) {
                $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_validation
            }
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should not remove jobs when -Job is null" {
            $nullVariable = $null
            $result = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $nullVariable
            $result | Should -BeNullOrEmpty
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_validation) | Should -Not -BeNullOrEmpty
        }

        It "Should not remove jobs when -Job is empty string" {
            $result = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "" -WarningAction SilentlyContinue
            $WarnVar | Should -BeLike "*Job  doesn't exist*"
            $result | Should -BeNullOrEmpty
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_validation) | Should -Not -BeNullOrEmpty
        }

        It "Should not remove jobs when -Job is whitespace" {
            $result = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "   "
            $result | Should -BeNullOrEmpty
            (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job dbatoolsci_testjob_validation) | Should -Not -BeNullOrEmpty
        }
    }

    Context "The connection of the caller keeps its database (#10555)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $contextJobName = "dbatoolsci_testjob_context"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $contextJobName

            # sp_delete_job used to be run through the msdb database, which leaves the connection of the
            # caller there. Only a non-pooled connection shows it, because SMO reopens a pooled one at its
            # default database.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $null = Remove-DbaAgentJob -SqlInstance $callerServer -Job $contextJobName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance
            $null = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $contextJobName | Remove-DbaAgentJob -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "still removes the job" {
            Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $contextJobName | Should -BeNullOrEmpty
        }

        It "leaves the connection in the database it was on" {
            $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be "master"
        }
    }
}