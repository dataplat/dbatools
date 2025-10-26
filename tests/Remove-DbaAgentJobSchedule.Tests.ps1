#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentJobSchedule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Job",
                "Schedule",
                "ScheduleUid",
                "ScheduleId",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $jobName = "dbatoolsci_detach_job_$(Get-Random)"
        $scheduleName1 = "dbatoolsci_detach_schedule1_$(Get-Random)"
        $scheduleName2 = "dbatoolsci_detach_schedule2_$(Get-Random)"
    }

    AfterAll {
        # Cleanup
        Remove-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule $scheduleName1, $scheduleName2 -Confirm:$false -ErrorAction SilentlyContinue -Force
    }

    Context "When detaching schedules from jobs" {
        BeforeAll {
            # Create a test job
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Description "Test job for schedule detachment"

            # Create test schedules
            $null = New-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule $scheduleName1 -FrequencyType Daily -FrequencyInterval 1 -Force
            $null = New-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule $scheduleName2 -FrequencyType Daily -FrequencyInterval 1 -Force

            # Attach schedules to the job
            $null = Set-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Schedule $scheduleName1, $scheduleName2
        }

        It "Should detach a schedule by name" {
            $result = Remove-DbaAgentJobSchedule -SqlInstance $script:instance2 -Job $jobName -Schedule $scheduleName1
            $result.IsDetached | Should -Be $true
            $result.Schedule | Should -Be $scheduleName1
            $result.Job | Should -Be $jobName

            # Verify the schedule was detached from the job
            $job = Get-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName
            $job.JobSchedules.Name | Should -Not -Contain $scheduleName1

            # Verify the schedule still exists
            $schedule = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule $scheduleName1
            $schedule | Should -Not -BeNullOrEmpty
        }

        It "Should detach a schedule by ID" {
            # Get the schedule ID
            $schedule = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule $scheduleName2
            $scheduleId = $schedule.ID

            $result = Remove-DbaAgentJobSchedule -SqlInstance $script:instance2 -Job $jobName -ScheduleId $scheduleId
            $result.IsDetached | Should -Be $true
            $result.ScheduleId | Should -Be $scheduleId

            # Verify the schedule was detached from the job
            $job = Get-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName
            $job.JobSchedules.Name | Should -Not -Contain $scheduleName2

            # Verify the schedule still exists
            $scheduleCheck = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule $scheduleName2
            $scheduleCheck | Should -Not -BeNullOrEmpty
        }

        It "Should work with pipeline input" {
            # Re-attach a schedule for testing
            $null = Set-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Schedule $scheduleName1

            $job = Get-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName
            $result = $job | Remove-DbaAgentJobSchedule -Schedule $scheduleName1
            $result.IsDetached | Should -Be $true
            $result.Job | Should -Be $jobName
        }

        It "Should support -WhatIf" {
            # Re-attach a schedule for testing
            $null = Set-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Schedule $scheduleName1

            Remove-DbaAgentJobSchedule -SqlInstance $script:instance2 -Job $jobName -Schedule $scheduleName1 -WhatIf

            # Verify the schedule was NOT detached
            $job = Get-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName
            $job.JobSchedules.Name | Should -Contain $scheduleName1
        }
    }
}
