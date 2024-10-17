param($ModuleName = 'dbatools')

Describe "Set-DbaAgentSchedule" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentSchedule
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Job parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type Object[] -Not -Mandatory
        }
        It "Should have ScheduleName parameter" {
            $CommandUnderTest | Should -HaveParameter ScheduleName -Type String -Not -Mandatory
        }
        It "Should have NewName parameter" {
            $CommandUnderTest | Should -HaveParameter NewName -Type String -Not -Mandatory
        }
        It "Should have Enabled parameter" {
            $CommandUnderTest | Should -HaveParameter Enabled -Type Switch -Not -Mandatory
        }
        It "Should have Disabled parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type Switch -Not -Mandatory
        }
        It "Should have FrequencyType parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencyType -Type Object -Not -Mandatory
        }
        It "Should have FrequencyInterval parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencyInterval -Type Object[] -Not -Mandatory
        }
        It "Should have FrequencySubdayType parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencySubdayType -Type Object -Not -Mandatory
        }
        It "Should have FrequencySubdayInterval parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencySubdayInterval -Type Int32 -Not -Mandatory
        }
        It "Should have FrequencyRelativeInterval parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencyRelativeInterval -Type Object -Not -Mandatory
        }
        It "Should have FrequencyRecurrenceFactor parameter" {
            $CommandUnderTest | Should -HaveParameter FrequencyRecurrenceFactor -Type Int32 -Not -Mandatory
        }
        It "Should have StartDate parameter" {
            $CommandUnderTest | Should -HaveParameter StartDate -Type String -Not -Mandatory
        }
        It "Should have EndDate parameter" {
            $CommandUnderTest | Should -HaveParameter EndDate -Type String -Not -Mandatory
        }
        It "Should have StartTime parameter" {
            $CommandUnderTest | Should -HaveParameter StartTime -Type String -Not -Mandatory
        }
        It "Should have EndTime parameter" {
            $CommandUnderTest | Should -HaveParameter EndTime -Type String -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Not -Mandatory
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $null = New-DbaAgentJob -SqlInstance $env:instance2 -Job 'dbatoolsci_setschedule1' -OwnerLogin 'sa'
            $null = New-DbaAgentJob -SqlInstance $env:instance2 -Job 'dbatoolsci_setschedule2' -OwnerLogin 'sa'
            $start = (Get-Date).AddDays(2).ToString('yyyyMMdd')
            $end = (Get-Date).AddDays(4).ToString('yyyyMMdd')
            $altstart = (Get-Date).AddDays(3).ToString('yyyyMMdd')
            $altend = (Get-Date).AddDays(5).ToString('yyyyMMdd')
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $env:instance2 -Job 'dbatoolsci_setschedule1', 'dbatoolsci_setschedule2' -Confirm:$false
        }

        Context "Should rename schedule" {
            BeforeAll {
                $variables = @{
                    SqlInstance               = $env:instance2
                    Schedule                  = 'dbatoolsci_oldname'
                    Job                       = 'dbatoolsci_setschedule1'
                    FrequencyRecurrenceFactor = '1'
                    FrequencySubdayInterval   = '5'
                    FrequencySubdayType       = 'Time'
                    StartDate                 = $start
                    StartTime                 = '010000'
                    EndDate                   = $end
                    EndTime                   = '020000'
                }

                $null = New-DbaAgentSchedule @variables
            }
            AfterAll {
                $null = Get-DbaAgentSchedule -SqlInstance $env:instance2 |
                    Where-Object { $_.name -like 'dbatools*' } |
                    Remove-DbaAgentSchedule -Confirm:$false -Force
            }

            It "Should rename the schedule" {
                $schedules = Get-DbaAgentSchedule -SqlInstance $env:instance2 | Where-Object { $_.name -like 'dbatools*' }
                $variables = @{
                    SqlInstance               = $env:instance2
                    Schedule                  = "dbatoolsci_oldname"
                    NewName                   = "dbatoolsci_newname"
                    Job                       = 'dbatoolsci_setschedule1'
                    FrequencyRecurrenceFactor = '6'
                    FrequencySubdayInterval   = '4'
                    StartDate                 = $altstart
                    StartTime                 = '113300'
                    EndDate                   = $altend
                    EndTime                   = '221100'
                }

                $null = Set-DbaAgentSchedule @variables
                $results = Get-DbaAgentSchedule -SqlInstance $env:instance2 | Where-Object { $_.name -like 'dbatools*' }

                $results | Should -Not -BeNullOrEmpty
                foreach ($r in $results) {
                    $r.name | Should -Not -Be $schedules.where({ $_.id -eq $r.id }).name
                }
            }
        }

        Context "Should set schedules based on static frequency" {
            BeforeAll {
                foreach ($frequency in ('Once', 'AgentStart', 'IdleComputer')) {
                    $variables = @{
                        SqlInstance               = $env:instance2
                        Schedule                  = "dbatoolsci_$frequency"
                        Job                       = 'dbatoolsci_setschedule1'
                        FrequencyType             = $frequency
                        FrequencyRecurrenceFactor = '1'
                    }

                    if ($frequency -ne 'IdleComputer') {
                        $null = New-DbaAgentSchedule -StartDate $start -StartTime '010000' -EndDate $end -EndTime '020000' @variables
                    } else {
                        $null = New-DbaAgentSchedule -Disabled -Force @variables
                    }
                }
            }
            AfterAll {
                $null = Get-DbaAgentSchedule -SqlInstance $env:instance2 |
                    Where-Object { $_.name -like 'dbatools*' } |
                    Remove-DbaAgentSchedule -Confirm:$false -Force
            }

            It "Should set schedules to OnIdle and Enabled" {
                $schedules = Get-DbaAgentSchedule -SqlInstance $env:instance2 | Where-Object { $_.name -like 'dbatools*' }
                foreach ($schedule in $schedules) {
                    foreach ($frequency in ('Once', '1' , 'AgentStart', '64', 'IdleComputer', '128')) {
                        $variables = @{
                            SqlInstance               = $env:instance2
                            Schedule                  = "$($schedule.name)"
                            Job                       = 'dbatoolsci_setschedule1'
                            FrequencyType             = $frequency
                            FrequencyRecurrenceFactor = '5'
                        }

                        if ($frequency -notin ('IdleComputer', '128')) {
                            $null = Set-DbaAgentSchedule -StartDate $altstart -StartTime '113300' -EndDate $altend -EndTime '221100' -Disabled @variables
                        } else {
                            $null = Set-DbaAgentSchedule -Enabled -Force @variables
                        }
                    }
                }
                $results = Get-DbaAgentSchedule -SqlInstance $env:instance2 | Where-Object { $_.name -like 'dbatools*' }

                $results | Should -Not -BeNullOrEmpty
                foreach ($r in $results) {
                    $r.FrequencyTypes | Should -Be 'OnIdle'
                    $r.isEnabled | Should -Be 'True'
                }
            }
        }

        Context "Should set schedules based on calendar frequency" {
            BeforeAll {
                foreach ($frequency in ('Daily', 'Weekly', 'Monthly', 'MonthlyRelative')) {
                    $variables = @{
                        SqlInstance               = $env:instance2
                        Schedule                  = "dbatoolsci_$frequency"
                        Job                       = 'dbatoolsci_setschedule2'
                        FrequencyType             = $frequency
                        FrequencyRecurrenceFactor = '1'
                        FrequencyInterval         = '1'
                        FrequencyRelativeInterval = 'First'
                        StartDate                 = $start
                        StartTime                 = '010000'
                        EndDate                   = $end
                        EndTime                   = '020000'
                    }

                    $null = New-DbaAgentSchedule @variables
                }
            }
            AfterAll {
                $null = Get-DbaAgentSchedule -SqlInstance $env:instance2 |
                    Where-Object { $_.name -like 'dbatools*' } |
                    Remove-DbaAgentSchedule -Confirm:$false -Force
            }

            It "Should set schedules to MonthlyRelative with updated times" {
                $schedules = Get-DbaAgentSchedule -SqlInstance $env:instance2 | Where-Object { $_.name -like 'dbatools*' }
                foreach ($schedule in $schedules) {
                    foreach ($frequency in ('Daily', '4', 'Weekly', '8', 'Monthly', '16', 'MonthlyRelative', '32')) {
                        $variables = @{
                            SqlInstance               = $env:instance2
                            Schedule                  = "$($schedule.name)"
                            Job                       = 'dbatoolsci_setschedule2'
                            FrequencyType             = $frequency
                            FrequencyRecurrenceFactor = '6'
                            FrequencyInterval         = '4'
                            FrequencyRelativeInterval = 'Second'
                            StartDate                 = $altstart
                            StartTime                 = '113300'
                            EndDate                   = $altend
                            EndTime                   = '221100'
                        }

                        $null = Set-DbaAgentSchedule @variables
                    }
                }
                $results = Get-DbaAgentSchedule -SqlInstance $env:instance2 | Where-Object { $_.name -like 'dbatools*' }

                $results | Should -Not -BeNullOrEmpty
                foreach ($r in $results) {
                    $r.FrequencyTypes | Should -Be 'MonthlyRelative'
                    $r.StartTime | Should -Not -Be $schedules.where({ $_.id -eq $r.id }).StartTime
                }
            }
        }

        Context "Should set schedules with various frequency subday type" {
            BeforeAll {
                foreach ($FrequencySubdayType in ('Once', 'Time', 'Seconds', 'Second', 'Minutes', 'Minute', 'Hours', 'Hour')) {
                    $variables = @{
                        SqlInstance               = $env:instance2
                        Schedule                  = "dbatoolsci_$FrequencySubdayType"
                        Job                       = 'dbatoolsci_setschedule1'
                        FrequencyRecurrenceFactor = '1'
                        FrequencySubdayInterval   = '5'
                        FrequencySubdayType       = $FrequencySubdayType
                        StartDate                 = $start
                        StartTime                 = '010000'
                        EndDate                   = $end
                        EndTime                   = '020000'
                    }

                    $null = New-DbaAgentSchedule @variables
                }
            }
            AfterAll {
                $null = Get-DbaAgentSchedule -SqlInstance $env:instance2 |
                    Where-Object { $_.name -like 'dbatools*' } |
                    Remove-DbaAgentSchedule -Confirm:$false -Force
            }

            It "Should set schedules with updated EndDate" {
                $schedules = Get-DbaAgentSchedule -SqlInstance $env:instance2 | Where-Object { $_.name -like 'dbatools*' }
                foreach ($schedule in $schedules) {
                    foreach ($FrequencySubdayType in ('Once', 'Time', 'Seconds', 'Second', 'Minutes', 'Minute', 'Hours', 'Hour')) {
                        $variables = @{
                            SqlInstance               = $env:instance2
                            Schedule                  = "$schedule"
                            Job                       = 'dbatoolsci_setschedule1'
                            FrequencyRecurrenceFactor = '6'
                            FrequencySubdayInterval   = '4'
                            FrequencySubdayType       = $FrequencySubdayType
                            StartDate                 = $altstart
                            StartTime                 = '113300'
                            EndDate                   = $altend
                            EndTime                   = '221100'
                        }

                        $null = Set-DbaAgentSchedule @variables
                    }
                }
                $results = Get-DbaAgentSchedule -SqlInstance $env:instance2 | Where-Object { $_.name -like 'dbatools*' }

                $results | Should -Not -BeNullOrEmpty
                foreach ($r in $results) {
                    $r.EndDate | Should -Not -Be $schedules.where({ $_.id -eq $r.id }).EndDate
                }
            }
        }

        Context "Should set schedules with various frequency relative interval" {
            BeforeAll {
                foreach ($FrequencyRelativeInterval in ('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')) {
                    $variables = @{
                        SqlInstance               = $env:instance2
                        Schedule                  = "dbatoolsci_$FrequencyRelativeInterval"
                        Job                       = 'dbatoolsci_setschedule2'
                        FrequencyRecurrenceFactor = '1'
                        FrequencyRelativeInterval = $FrequencyRelativeInterval
                        StartDate                 = $start
                        StartTime                 = '010000'
                        EndDate                   = $end
                        EndTime                   = '020000'
                    }

                    $null = New-DbaAgentSchedule @variables
                }
            }
            AfterAll {
                $null = Get-DbaAgentSchedule -SqlInstance $env:instance2 |
                    Where-Object { $_.name -like 'dbatools*' } |
                    Remove-DbaAgentSchedule -Confirm:$false -Force
            }

            It "Should set schedules with updated EndTime" {
                $schedules = Get-DbaAgentSchedule -SqlInstance $env:instance2 | Where-Object { $_.name -like 'dbatools*' }
                foreach ($schedule in $schedules) {
                    foreach ($FrequencyRelativeInterval in ('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')) {
                        $variables = @{
                            SqlInstance               = $env:instance2
                            Schedule                  = "$schedule"
                            Job                       = 'dbatoolsci_setschedule2'
                            FrequencyRecurrenceFactor = '4'
                            FrequencyRelativeInterval = $FrequencyRelativeInterval
                            StartDate                 = $altstart
                            StartTime                 = '113300'
                            EndDate                   = $altend
                            EndTime                   = '221100'
                        }

                        $null = Set-DbaAgentSchedule @variables
                    }
                }
                $results = Get-DbaAgentSchedule -SqlInstance $env:instance2 | Where-Object { $_.name -like 'dbatools*' }

                $results | Should -Not -BeNullOrEmpty
                foreach ($r in $results) {
                    $r.EndTime | Should -Not -Be $schedules.where({ $_.id -eq $r.id }).EndTime
                }
            }
        }
    }
}
