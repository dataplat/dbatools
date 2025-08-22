#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentSchedule",
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
                "Disabled",
                "FrequencyType",
                "FrequencyInterval",
                "FrequencySubdayType",
                "FrequencySubdayInterval",
                "FrequencyRelativeInterval",
                "FrequencyRecurrenceFactor",
                "StartDate",
                "EndDate",
                "StartTime",
                "EndTime",
                "Owner",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job 'dbatoolsci_newschedule' -OwnerLogin 'sa'
        $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job 'dbatoolsci_newschedule' -StepId 1 -StepName 'dbatoolsci Test Select' -Subsystem TransactSql -SubsystemServer $TestConfig.instance2 -Command "SELECT * FROM master.sys.all_columns;" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -DatabaseUser dbo

        $start = (Get-Date).AddDays(2).ToString('yyyyMMdd')
        $end = (Get-Date).AddDays(4).ToString('yyyyMMdd')
    }
    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job 'dbatoolsci_newschedule' -Confirm:$false
    }

    Context "Should create schedules based on frequency type" {
        BeforeAll {
            $results = @{ }

            $scheduleOptions = @('Once', 'OneTime', 'Daily', 'Weekly', 'Monthly', 'MonthlyRelative', 'AgentStart', 'AutoStart', 'IdleComputer', 'OnIdle')

            foreach ($frequency in $scheduleOptions) {
                $variables = @{SqlInstance    = $TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequency"
                    Job                       = 'dbatoolsci_newschedule'
                    FrequencyType             = $frequency
                    FrequencyRecurrenceFactor = '1'
                    FrequencyInterval         = '1'
                    FrequencyRelativeInterval = 'First'
                }

                if ($frequency -notin @('IdleComputer', 'OnIdle')) {
                    $results[$frequency] = $(New-DbaAgentSchedule -StartDate $start -StartTime '010000' -EndDate $end -EndTime '020000' @variables)
                } else {
                    $results[$frequency] = $(New-DbaAgentSchedule -Disabled -Force @variables)
                }
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.instance2 |
                Where-Object { $_.name -like 'dbatools*' } |
                Remove-DbaAgentSchedule -Confirm:$false -Force
            Remove-Variable -Name results
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have the correct frequency type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_newschedule).JobID
            foreach ($key in $results.keys) {
                $results[$key].EnumJobReferences() | Should -Contain $jobId
                $results[$key].FrequencyTypes | Should -BeIn $scheduleOptions
                $results[$key].JobCount | Should -Be 1

                if ($key -in @('IdleComputer', 'OnIdle')) {
                    $results[$key].FrequencyTypes | Should -Be "OnIdle"
                } elseif ($key -in @('Once', 'OneTime')) {
                    $results[$key].FrequencyTypes | Should -Be "OneTime"
                } elseif ($key -in @('AgentStart', 'AutoStart')) {
                    $results[$key].FrequencyTypes | Should -Be "AutoStart"
                } else {
                    $results[$key].FrequencyTypes | Should -Be $key
                }
            }
        }
    }

    Context "Should create schedules with various frequency interval" {
        BeforeAll {
            $results = @{ }

            foreach ($frequencyinterval in ('EveryDay', 'Weekdays', 'Weekend', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
                    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31)) {

                if ($frequencyinterval -is [int]) {
                    $frequencyType = "Monthly"
                } else {
                    $frequencyType = "Weekly"
                }

                $variables = @{SqlInstance    = $TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequencyinterval"
                    Job                       = 'dbatoolsci_newschedule'
                    FrequencyType             = $frequencyType
                    FrequencyRecurrenceFactor = '1'
                    FrequencyInterval         = $frequencyinterval
                    StartDate                 = $start
                    StartTime                 = '010000'
                    EndDate                   = $end
                    EndTime                   = '020000'
                }

                $results[$frequencyinterval] = $(New-DbaAgentSchedule @variables)
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.instance2 |
                Where-Object { $_.name -like 'dbatools*' } |
                Remove-DbaAgentSchedule -Confirm:$false -Force
            Remove-Variable -Name results
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have the correct interval for the frequency type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_newschedule).JobID
            foreach ($key in $results.keys) {
                $results[$key].EnumJobReferences() | Should -Contain $jobId

                if ($results[$key].FrequencyTypes -eq "Monthly") {
                    $results[$key].FrequencyInterval | Should -Be $key
                } elseif ($results[$key].FrequencyTypes -eq "Weekly") {
                    switch ($key) {
                        "Sunday" { $results[$key].FrequencyInterval | Should -Be 1 }
                        "Monday" { $results[$key].FrequencyInterval | Should -Be 2 }
                        "Tuesday" { $results[$key].FrequencyInterval | Should -Be 4 }
                        "Wednesday" { $results[$key].FrequencyInterval | Should -Be 8 }
                        "Thursday" { $results[$key].FrequencyInterval | Should -Be 16 }
                        "Friday" { $results[$key].FrequencyInterval | Should -Be 32 }
                        "Saturday" { $results[$key].FrequencyInterval | Should -Be 64 }
                        "Weekdays" { $results[$key].FrequencyInterval | Should -Be 62 }
                        "Weekend" { $results[$key].FrequencyInterval | Should -Be 65 }
                        "EveryDay" { $results[$key].FrequencyInterval | Should -Be 127 }
                    }
                }
            }
        }
    }

    Context "Should create schedules with various frequency subday type" {
        BeforeAll {
            $results = @{ }

            $scheduleOptions = @('Time', 'Once', 'Second', 'Seconds', 'Minute', 'Minutes', 'Hour', 'Hours')

            foreach ($frequencySubdayType in $scheduleOptions) {
                $variables = @{SqlInstance    = $TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequencySubdayType"
                    Job                       = 'dbatoolsci_newschedule'
                    FrequencyType             = 'Daily'
                    FrequencyInterval         = '1'
                    FrequencyRecurrenceFactor = '1'
                    FrequencySubdayInterval   = 10
                    FrequencySubdayType       = $frequencySubdayType
                    StartDate                 = $start
                    StartTime                 = '010000'
                    EndDate                   = $end
                    EndTime                   = '020000'
                }

                $results[$frequencySubdayType] = $(New-DbaAgentSchedule @variables)
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.instance2 |
                Where-Object { $_.name -like 'dbatools*' } |
                Remove-DbaAgentSchedule -Confirm:$false -Force
            Remove-Variable -Name results
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have a valid frequency subday type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_newschedule).JobID
            foreach ($key in $results.keys) {
                $results[$key].EnumJobReferences() | Should -Contain $jobId
                $results[$key].FrequencySubdayTypes | Should -BeIn $scheduleOptions

                if ($key -in @('Second', 'Seconds')) {
                    $results[$key].FrequencySubdayTypes | Should -Be "Second"
                } elseif ($key -in @('Minute', 'Minutes')) {
                    $results[$key].FrequencySubdayTypes | Should -Be "Minute"
                } elseif ($key -in @('Hour', 'Hours')) {
                    $results[$key].FrequencySubdayTypes | Should -Be "Hour"
                } elseif ($key -in @('Once', 'Time')) {
                    $results[$key].FrequencySubdayTypes | Should -Be "Once"
                } else {
                    $results[$key].FrequencySubdayTypes | Should -Be $key
                }
            }
        }
    }

    Context "Should create schedules with various frequency relative interval" {
        BeforeAll {
            $results = @{ }

            # Unused (value of 0) is not valid for sp_add_jobschedule when using the MonthlyRelative frequency type, so 'Unused' has been removed from this test.
            $scheduleOptions = @('First', 'Second', 'Third', 'Fourth', 'Last')

            foreach ($frequencyRelativeInterval in $scheduleOptions) {
                $variables = @{SqlInstance    = $TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequencyRelativeInterval"
                    Job                       = 'dbatoolsci_newschedule'
                    FrequencyType             = 'MonthlyRelative'           # required to set the FrequencyRelativeInterval
                    FrequencyRecurrenceFactor = '2'                         # every 2 months
                    FrequencyRelativeInterval = $frequencyRelativeInterval  # 'First', 'Second', 'Third', 'Fourth', 'Last'
                    FrequencyInterval         = '6'                         # Friday or day 6
                    FrequencySubDayInterval   = '1'                         # daily frequency 1="occurs once at..." or "occurs every..."
                    FrequencySubDayType       = 'Once'
                    StartDate                 = $start
                    StartTime                 = '010000'
                    EndDate                   = $end
                    EndTime                   = '020000'
                }

                $results[$frequencyRelativeInterval] = $(New-DbaAgentSchedule @variables)
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.instance2 |
                Where-Object { $_.name -like 'dbatools*' } |
                Remove-DbaAgentSchedule -Confirm:$false -Force
            Remove-Variable -Name results
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have a valid frequency relative interval" {
            $jobId = (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job dbatoolsci_newschedule).JobID
            foreach ($key in $results.keys) {
                $results[$key].EnumJobReferences() | Should -Contain $jobId
                $results[$key].FrequencyRelativeIntervals | Should -BeIn $scheduleOptions
                $results[$key].FrequencyRelativeIntervals | Should -Be $key
            }
        }
    }
}