#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentSchedule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Schedule",
                "Id",
                "InputObject",
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

        # Create the schedule on the source instance
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $sql = "EXEC msdb.dbo.sp_add_schedule @schedule_name = N'dbatoolsci_DailySchedule' , @freq_type = 4, @freq_interval = 1, @active_start_time = 010000"
        $server.Query($sql)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up the schedules from both instances
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $sql = "EXEC msdb.dbo.sp_delete_schedule @schedule_name = 'dbatoolsci_DailySchedule'"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
        $sql = "EXEC msdb.dbo.sp_delete_schedule @schedule_name = 'dbatoolsci_DailySchedule'"
        $server.Query($sql)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying agent schedule between instances" {
        BeforeAll {
            $results = @(Copy-DbaAgentSchedule -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2)
        }

        It "Returns more than one result" {
            $results.Status.Count | Should -BeGreaterThan 1
        }

        It "Contains at least one successful copy" {
            $results | Where-Object Status -eq "Successful" | Should -Not -BeNullOrEmpty
        }

        It "Creates schedule with correct start time" {
            $schedule = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceCopy2 -Schedule dbatoolsci_DailySchedule
            $schedule.ActiveStartTimeOfDay | Should -Be "01:00:00"
        }
    }

    Context "When the destination schedule has no associated jobs and -Force is used" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The same schedule name on both instances, but with different start times, so we can
            # tell a real drop and recreate from a silent no-op. The destination copy has no jobs.
            $splatSourceForceSchedule = @{
                SqlInstance       = $TestConfig.InstanceCopy1
                Schedule          = "dbatoolsci_ForceSchedule"
                FrequencyType     = "Daily"
                FrequencyInterval = "Everyday"
                StartTime         = "010000"
                Force             = $true
            }
            $null = New-DbaAgentSchedule @splatSourceForceSchedule

            $splatDestForceSchedule = @{
                SqlInstance       = $TestConfig.InstanceCopy2
                Schedule          = "dbatoolsci_ForceSchedule"
                FrequencyType     = "Daily"
                FrequencyInterval = "Everyday"
                StartTime         = "050000"
                Force             = $true
            }
            $null = New-DbaAgentSchedule @splatDestForceSchedule

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatCopyForce = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Schedule    = "dbatoolsci_ForceSchedule"
                Force       = $true
            }
            $forceResults = @(Copy-DbaAgentSchedule @splatCopyForce)
            $forceSchedules = @(Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceCopy2 -Schedule dbatoolsci_ForceSchedule)
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaAgentSchedule -SqlInstance $TestConfig.InstanceCopy1 -Schedule dbatoolsci_ForceSchedule -ErrorAction SilentlyContinue
            $null = Remove-DbaAgentSchedule -SqlInstance $TestConfig.InstanceCopy2 -Schedule dbatoolsci_ForceSchedule -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Does not warn" {
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Reports the schedule as copied" {
            $forceResults.Status | Should -Be "Successful"
        }

        It "Replaces the destination schedule with the source definition" {
            $forceSchedules.ActiveStartTimeOfDay | Should -Be "01:00:00"
        }

        It "Leaves exactly one schedule with that name on the destination" {
            $forceSchedules.Count | Should -Be 1
        }
    }

    Context "When the destination schedule has associated jobs and -Force is used" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatSourceJobSchedule = @{
                SqlInstance       = $TestConfig.InstanceCopy1
                Schedule          = "dbatoolsci_JobSchedule"
                FrequencyType     = "Daily"
                FrequencyInterval = "Everyday"
                StartTime         = "010000"
                Force             = $true
            }
            $null = New-DbaAgentSchedule @splatSourceJobSchedule

            # A schedule that a job uses cannot be dropped, so -Force must skip it and leave it alone.
            $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job dbatoolsci_ScheduleJob
            $splatDestJobSchedule = @{
                SqlInstance       = $TestConfig.InstanceCopy2
                Job               = "dbatoolsci_ScheduleJob"
                Schedule          = "dbatoolsci_JobSchedule"
                FrequencyType     = "Daily"
                FrequencyInterval = "Everyday"
                StartTime         = "050000"
                Force             = $true
            }
            $null = New-DbaAgentSchedule @splatDestJobSchedule

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatCopyJobSchedule = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Schedule    = "dbatoolsci_JobSchedule"
                Force       = $true
            }
            $jobScheduleResults = @(Copy-DbaAgentSchedule @splatCopyJobSchedule)
            $jobSchedules = @(Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceCopy2 -Schedule dbatoolsci_JobSchedule)
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceCopy2 -Job dbatoolsci_ScheduleJob -KeepUnusedSchedule -ErrorAction SilentlyContinue
            $null = Remove-DbaAgentSchedule -SqlInstance $TestConfig.InstanceCopy1 -Schedule dbatoolsci_JobSchedule -ErrorAction SilentlyContinue
            $null = Remove-DbaAgentSchedule -SqlInstance $TestConfig.InstanceCopy2 -Schedule dbatoolsci_JobSchedule -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Does not warn" {
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Reports the schedule as skipped" {
            $jobScheduleResults.Status | Should -Be "Skipped"
            $jobScheduleResults.Notes | Should -Be "Schedule has associated jobs"
        }

        It "Leaves the destination schedule unchanged" {
            $jobSchedules.ActiveStartTimeOfDay | Should -Be "05:00:00"
        }
    }
}
