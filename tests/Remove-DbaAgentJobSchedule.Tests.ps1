#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Remove-DbaAgentJobSchedule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

class MockAgentServer {
    [string]$Name
    [string]$ComputerName
    [string]$ServiceName
    [string]$DomainInstanceName
    [object]$JobServer

    MockAgentServer([string]$Name) {
        $this.Name = $Name
        $this.ComputerName = $Name
        $this.ServiceName = "MSSQLSERVER"
        $this.DomainInstanceName = $Name
    }

    [string] ToString() {
        return $this.Name
    }
}

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

    InModuleScope "dbatools" {
        BeforeAll {
            function New-MockAgentSchedule {
                param(
                    [string]$Name,
                    [int]$Id,
                    [switch]$ThrowOnDrop
                )

                $schedule = [PSCustomObject]@{
                    Name         = $Name
                    Id           = $Id
                    ScheduleUid  = [guid]::NewGuid()
                    DropCount    = 0
                    KeepSchedule = $null
                    ThrowOnDrop  = $ThrowOnDrop
                }
                $schedule | Add-Member -MemberType ScriptMethod -Name Drop -Value {
                    param([bool]$keepSchedule)

                    $this.DropCount++
                    $this.KeepSchedule = $keepSchedule

                    if ($this.ThrowOnDrop) {
                        throw "drop failed for $($this.Name)"
                    }
                } -Force

                return $schedule
            }

            function New-MockAgentJob {
                param(
                    [string]$Name,
                    [object[]]$JobSchedules
                )

                return [PSCustomObject]@{
                    Name         = $Name
                    Parent       = $null
                    JobSchedules = $JobSchedules
                }
            }

            function New-MockAgentServer {
                param([object[]]$Job)

                $jobs = @{ }
                foreach ($jobObject in $Job) {
                    $jobs[$jobObject.Name] = $jobObject
                }
                $jobs | Add-Member -MemberType ScriptProperty -Name Name -Value { $this.Keys } -Force

                $server = [MockAgentServer]::new("sql1")
                $jobServer = [PSCustomObject]@{
                    Parent = $server
                    Jobs   = $jobs
                }
                $server.JobServer = $jobServer

                foreach ($jobObject in $Job) {
                    $jobObject.Parent = $jobServer
                }

                return $server
            }
        }

        Context "When multiple schedules with the same name are attached to a job" {
            BeforeAll {
                $script:scheduleOne = New-MockAgentSchedule -Name "SharedSchedule" -Id 1
                $script:scheduleTwo = New-MockAgentSchedule -Name "SharedSchedule" -Id 2
                $job = New-MockAgentJob -Name "Job1" -JobSchedules @($script:scheduleOne, $script:scheduleTwo)
                $script:mockServer = New-MockAgentServer -Job $job

                Mock Connect-DbaInstance { $script:mockServer }
            }

            It "Should detach each matching schedule instead of failing on an array of job schedules" {
                $splatDetach = @{
                    SqlInstance = "sql1"
                    Job         = "Job1"
                    Schedule    = "SharedSchedule"
                    Confirm     = $false
                }
                $result = Remove-DbaAgentJobSchedule @splatDetach

                $result.Count | Should -Be 2
                ($result | Where-Object IsDetached).Count | Should -Be 2
                ($result | Select-Object -ExpandProperty ScheduleId) | Should -Be @(1, 2)
                $script:scheduleOne.DropCount | Should -Be 1
                $script:scheduleTwo.DropCount | Should -Be 1
                $script:scheduleOne.KeepSchedule | Should -Be $true
                $script:scheduleTwo.KeepSchedule | Should -Be $true
            }
        }

        Context "When detaching a schedule fails" {
            BeforeAll {
                $script:failingSchedule = New-MockAgentSchedule -Name "BrokenSchedule" -Id 9 -ThrowOnDrop
                $job = New-MockAgentJob -Name "Job1" -JobSchedules $script:failingSchedule
                $script:mockServer = New-MockAgentServer -Job $job

                Mock Connect-DbaInstance { $script:mockServer }
                Mock Stop-Function { }
            }

            It "Should return the failed detach result instead of skipping output" {
                $splatDetach = @{
                    SqlInstance = "sql1"
                    Job         = "Job1"
                    Schedule    = "BrokenSchedule"
                    Confirm     = $false
                }
                $result = Remove-DbaAgentJobSchedule @splatDetach

                $result | Should -Not -BeNullOrEmpty
                $result.IsDetached | Should -Be $false
                $result.Status | Should -Match "drop failed for BrokenSchedule"
                $script:failingSchedule.DropCount | Should -Be 1
            }
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