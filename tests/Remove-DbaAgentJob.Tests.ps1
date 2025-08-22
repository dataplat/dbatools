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

            $null = New-DbaAgentSchedule -SqlInstance $TestConfig.instance3 -Schedule dbatoolsci_daily -FrequencyType Daily -FrequencyInterval Everyday -Force
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob -Schedule dbatoolsci_daily
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command "select 1"
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob -Confirm:$false
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if (Get-DbaAgentSchedule -SqlInstance $TestConfig.instance3 -Schedule dbatoolsci_daily) {
                Remove-DbaAgentSchedule -SqlInstance $TestConfig.instance3 -Schedule dbatoolsci_daily -Confirm:$false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have deleted job: dbatoolsci_testjob" {
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob) | Should -BeNullOrEmpty
        }

        It "Should have deleted schedule: dbatoolsci_daily" {
            (Get-DbaAgentSchedule -SqlInstance $TestConfig.instance3 -Schedule dbatoolsci_daily) | Should -BeNullOrEmpty
        }

        It "Should have deleted history: dbatoolsci_daily" {
            (Get-DbaAgentJobHistory -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob) | Should -BeNullOrEmpty
        }
    }

    Context "Command removes job but not schedule" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = New-DbaAgentSchedule -SqlInstance $TestConfig.instance3 -Schedule dbatoolsci_weekly -FrequencyType Weekly -FrequencyInterval Everyday -Force
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob_schedule -Schedule dbatoolsci_weekly
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob_schedule -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command "select 1"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob_schedule -KeepUnusedSchedule -Confirm:$false
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            if (Get-DbaAgentSchedule -SqlInstance $TestConfig.instance3 -Schedule dbatoolsci_weekly) {
                Remove-DbaAgentSchedule -SqlInstance $TestConfig.instance3 -Schedule dbatoolsci_weekly -Confirm:$false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have deleted job: dbatoolsci_testjob_schedule" {
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob_schedule) | Should -BeNullOrEmpty
        }

        It "Should not have deleted schedule: dbatoolsci_weekly" {
            (Get-DbaAgentSchedule -SqlInstance $TestConfig.instance3 -Schedule dbatoolsci_weekly) | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command removes job but not history and supports piping" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $jobId = New-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob_history | Select-Object -ExpandProperty JobId
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob_history -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command "select 1"
            $null = Start-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob_history
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server.Query("delete from sysjobhistory where job_id = '$jobId'", "msdb")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have deleted job: dbatoolsci_testjob_history" {
            $null = Get-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob_history | Remove-DbaAgentJob -KeepHistory -Confirm:$false
            (Get-DbaAgentJob -SqlInstance $TestConfig.instance3 -Job dbatoolsci_testjob_history) | Should -BeNullOrEmpty
        }

        It -Skip:$true "Should not have deleted history: dbatoolsci_testjob_history" {
            ($server.Query("select 1 from sysjobhistory where job_id = '$jobId'", "msdb")) | Should -Not -BeNullOrEmpty
        }
    }
} # $TestConfig.instance2 for appveyor