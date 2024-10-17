param($ModuleName = 'dbatools')

Describe "New-DbaAgentSchedule Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentSchedule
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type Object[] -Not -Mandatory
        }
        It "Should have Schedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schedule -Type Object -Not -Mandatory
        }
        It "Should have Disabled as a parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type SwitchParameter -Not -Mandatory
        }
        It "Should have FrequencyType as a parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencyType -Type Object -Not -Mandatory
        }
        It "Should have FrequencyInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencyInterval -Type Object[] -Not -Mandatory
        }
        It "Should have FrequencySubdayType as a parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencySubdayType -Type Object -Not -Mandatory
        }
        It "Should have FrequencySubdayInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencySubdayInterval -Type Int32 -Not -Mandatory
        }
        It "Should have FrequencyRelativeInterval as a parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencyRelativeInterval -Type Object -Not -Mandatory
        }
        It "Should have FrequencyRecurrenceFactor as a parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencyRecurrenceFactor -Type Int32 -Not -Mandatory
        }
        It "Should have StartDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartDate -Type String -Not -Mandatory
        }
        It "Should have EndDate as a parameter" {
            $CommandUnderTest | Should -HaveParameter EndDate -Type String -Not -Mandatory
        }
        It "Should have StartTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartTime -Type String -Not -Mandatory
        }
        It "Should have EndTime as a parameter" {
            $CommandUnderTest | Should -HaveParameter EndTime -Type String -Not -Mandatory
        }
        It "Should have Owner as a parameter" {
            $CommandUnderTest | Should -HaveParameter Owner -Type String -Not -Mandatory
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

Describe "New-DbaAgentSchedule Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_newschedule' -OwnerLogin 'sa'
        $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job 'dbatoolsci_newschedule' -StepId 1 -StepName 'dbatoolsci Test Select' -Subsystem TransactSql -SubsystemServer $script:instance2 -Command "SELECT * FROM master.sys.all_columns;" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -DatabaseUser sa

        $start = (Get-Date).AddDays(2).ToString('yyyyMMdd')
        $end = (Get-Date).AddDays(4).ToString('yyyyMMdd')
    }
    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_newschedule' -Confirm:$false
    }

    Context "Should create schedules based on frequency type" {
        BeforeAll {
            $results = @{}

            $scheduleOptions = @('Once', 'OneTime', 'Daily', 'Weekly', 'Monthly', 'MonthlyRelative', 'AgentStart', 'AutoStart', 'IdleComputer', 'OnIdle')

            foreach ($frequency in $scheduleOptions) {
                $variables = @{
                    SqlInstance               = $script:instance2
                    Schedule                  = "dbatoolsci_$frequency"
                    Job                       = 'dbatoolsci_newschedule'
                    FrequencyType             = $frequency
                    FrequencyRecurrenceFactor = '1'
                    FrequencyInterval         = '1'
                    FrequencyRelativeInterval = 'First'
                }

                if ($frequency -notin @('IdleComputer', 'OnIdle')) {
                    $results[$frequency] = New-DbaAgentSchedule -StartDate $start -StartTime '010000' -EndDate $end -EndTime '020000' @variables
                } else {
                    $results[$frequency] = New-DbaAgentSchedule -Disabled -Force @variables
                }
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object { $_.name -like 'dbatools*' } |
                Remove-DbaAgentSchedule -Confirm:$false -Force
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have the correct frequency type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_newschedule).JobID
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
            $results = @{}

            foreach ($frequencyinterval in ('EveryDay', 'Weekdays', 'Weekend', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
                    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31)) {

                if ($frequencyinterval -is [int]) {
                    $frequencyType = "Monthly"
                } else {
                    $frequencyType = "Weekly"
                }

                $variables = @{
                    SqlInstance               = $script:instance2
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

                $results[$frequencyinterval] = New-DbaAgentSchedule @variables
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object { $_.name -like 'dbatools*' } |
                Remove-DbaAgentSchedule -Confirm:$false -Force
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have the correct interval for the frequency type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_newschedule).JobID
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
            $results = @{}

            $scheduleOptions = @('Time', 'Once', 'Second', 'Seconds', 'Minute', 'Minutes', 'Hour', 'Hours')

            foreach ($frequencySubdayType in $scheduleOptions) {
                $variables = @{
                    SqlInstance               = $script:instance2
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

                $results[$frequencySubdayType] = New-DbaAgentSchedule @variables
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object { $_.name -like 'dbatools*' } |
                Remove-DbaAgentSchedule -Confirm:$false -Force
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have a valid frequency subday type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_newschedule).JobID
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
            $results = @{}

            $scheduleOptions = @('First', 'Second', 'Third', 'Fourth', 'Last')

            foreach ($frequencyRelativeInterval in $scheduleOptions) {
                $variables = @{
                    SqlInstance               = $script:instance2
                    Schedule                  = "dbatoolsci_$frequencyRelativeInterval"
                    Job                       = 'dbatoolsci_newschedule'
                    FrequencyType             = 'MonthlyRelative'
                    FrequencyRecurrenceFactor = '2'
                    FrequencyRelativeInterval = $frequencyRelativeInterval
                    FrequencyInterval         = '6'
                    FrequencySubDayInterval   = '1'
                    FrequencySubDayType       = 'Once'
                    StartDate                 = $start
                    StartTime                 = '010000'
                    EndDate                   = $end
                    EndTime                   = '020000'
                }

                $results[$frequencyRelativeInterval] = New-DbaAgentSchedule @variables
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object { $_.name -like 'dbatools*' } |
                Remove-DbaAgentSchedule -Confirm:$false -Force
        }

        It "Should have Results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have a valid frequency relative interval" {
            $jobId = (Get-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_newschedule).JobID
            foreach ($key in $results.keys) {
                $results[$key].EnumJobReferences() | Should -Contain $jobId
                $results[$key].FrequencyRelativeIntervals | Should -BeIn $scheduleOptions
                $results[$key].FrequencyRelativeIntervals | Should -Be $key
            }
        }
    }
}
