#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentJobSchedule",
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
                "InputObject",
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

        $jobName = "dbatoolsci_job_$(Get-Random)"
        $scheduleName = "dbatoolsci_schedule_$(Get-Random)"

        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName

        $splatSchedule = @{
            SqlInstance       = $TestConfig.InstanceSingle
            Schedule          = $scheduleName
            FrequencyType     = "Daily"
            FrequencyInterval = 1
            StartTime         = "010000"
            Force             = $true
        }
        $null = New-DbaAgentSchedule @splatSchedule

        $splatAttach = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = $jobName
            Schedule    = $scheduleName
        }
        $null = Set-DbaAgentJob @splatAttach

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName
        $null = Remove-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule $scheduleName -Force

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When detaching a schedule from a job" {
        It "Should detach the schedule and return the expected output" {
            $splatDetach = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                Schedule    = $scheduleName
            }
            $result = Remove-DbaAgentJobSchedule @splatDetach
            $result.IsDetached | Should -Be $true
            $result.Job | Should -Be $jobName
            $result.Schedule | Should -Be $scheduleName
            $result.Status | Should -Be "Detached"
        }

        It "Should not remove the schedule itself after detaching" {
            $schedule = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule $scheduleName
            $schedule | Should -Not -BeNullOrEmpty
        }

        It "Should warn when the schedule is not attached to the job" {
            $splatDetach = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Job           = $jobName
                Schedule      = $scheduleName
                WarningAction = "SilentlyContinue"
            }
            $result = Remove-DbaAgentJobSchedule @splatDetach
            $result | Should -BeNullOrEmpty
            $WarnVar | Should -BeLike "*Schedule '$scheduleName' is not attached to job '$jobName'*"
        }
    }

    Context "When using pipeline input" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Reattach the schedule so we can test pipeline detachment
            $splatAttach = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = $jobName
                Schedule    = $scheduleName
            }
            $null = Set-DbaAgentJob @splatAttach

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should detach the schedule when job is piped in" {
            $result = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job $jobName | Remove-DbaAgentJobSchedule -Schedule $scheduleName
            $result.IsDetached | Should -Be $true
            $result.Job | Should -Be $jobName
        }
    }
}
