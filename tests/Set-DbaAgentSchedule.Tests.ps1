#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentSchedule",
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
                "NewName",
                "Enabled",
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
                "EnableException",
                "Force"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should have ScheduleName as an alias for Schedule parameter" {
            $aliases = (Get-Command $CommandName).Parameters["Schedule"].Aliases
            $aliases | Should -Contain "ScheduleName"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_setschedule1" -OwnerLogin "sa"
        $null = New-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_setschedule2" -OwnerLogin "sa"
        $start = (Get-Date).AddDays(2).ToString("yyyyMMdd")
        $end = (Get-Date).AddDays(4).ToString("yyyyMMdd")
        $altstart = (Get-Date).AddDays(3).ToString("yyyyMMdd")
        $altend = (Get-Date).AddDays(5).ToString("yyyyMMdd")
    }
    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job "dbatoolsci_setschedule1", "dbatoolsci_setschedule2"
    }
    Context "Should rename schedule" {
        BeforeAll {
            $splatCreateSchedule = @{
                SqlInstance               = $TestConfig.InstanceSingle
                Schedule                  = "dbatoolsci_oldname"
                Job                       = "dbatoolsci_setschedule1"
                FrequencyRecurrenceFactor = "1"
                FrequencySubdayInterval   = "5"
                FrequencySubdayType       = "Time"
                StartDate                 = $start
                StartTime                 = "010000"
                EndDate                   = $end
                EndTime                   = "020000"
            }

            $null = New-DbaAgentSchedule @splatCreateSchedule

            $schedules = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"

            $splatSetSchedule = @{
                SqlInstance               = $TestConfig.InstanceSingle
                Schedule                  = "dbatoolsci_oldname"
                NewName                   = "dbatoolsci_newname"
                Job                       = "dbatoolsci_setschedule1"
                FrequencyRecurrenceFactor = "6"
                FrequencySubdayInterval   = "4"
                StartDate                 = $altstart
                StartTime                 = "113300"
                EndDate                   = $altend
                EndTime                   = "221100"
            }

            $null = Set-DbaAgentSchedule @splatSetSchedule
            $renameScheduleResults = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"
        }

        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Force
        }

        It "Should have Results" {
            $renameScheduleResults | Should -Not -BeNullOrEmpty
        }

        foreach ($r in $renameScheduleResults) {
            It "$($r.name) Should have different name" {
                $r.name | Should -Not -Be "$($schedules.where({$PSItem.id -eq $r.id}).name)"
            }
        }
    }

    Context "Should set schedules based on static frequency" {
        BeforeAll {
            foreach ($frequency in ("Once", "AgentStart", "IdleComputer")) {
                $splatNewSchedule = @{
                    SqlInstance               = $TestConfig.InstanceSingle
                    Schedule                  = "dbatoolsci_$frequency"
                    Job                       = "dbatoolsci_setschedule1"
                    FrequencyType             = $frequency
                    FrequencyRecurrenceFactor = "1"
                }

                if ($frequency -ne "IdleComputer") {
                    $null = New-DbaAgentSchedule -StartDate $start -StartTime "010000" -EndDate $end -EndTime "020000" @splatNewSchedule
                } else {
                    $null = New-DbaAgentSchedule -Disabled -Force @splatNewSchedule
                }
            }

            $schedules = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"

            foreach ($schedule in $schedules) {
                foreach ($frequency in ("Once", "1" , "AgentStart", "64", "IdleComputer", "128")) {
                    $splatSetSchedule = @{
                        SqlInstance               = $TestConfig.InstanceSingle
                        Schedule                  = "$($schedule.name)"
                        Job                       = "dbatoolsci_setschedule1"
                        FrequencyType             = $frequency
                        FrequencyRecurrenceFactor = "5"
                    }

                    if ($frequency -notin ("IdleComputer", "128")) {
                        $null = Set-DbaAgentSchedule -StartDate $altstart -StartTime "113300" -EndDate $altend -EndTime "221100" -Disabled @splatSetSchedule
                    } else {
                        $null = Set-DbaAgentSchedule -Enabled -Force @splatSetSchedule
                    }
                }
            }

            $staticFrequencyResults = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"
        }

        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Force
        }

        It "Should have Results" {
            $staticFrequencyResults | Should -Not -BeNullOrEmpty
        }

        foreach ($r in $staticFrequencyResults) {
            It "$($r.name) Should have a frequency of OnIdle" {
                $r.FrequencyTypes | Should -Be "OnIdle"
            }
            It "$($r.name) Should be Enabled" {
                $r.isEnabled | Should -Be "True"
            }
        }
    }

    Context "Should set schedules based on calendar frequency" {
        BeforeAll {
            foreach ($frequency in ("Daily", "Weekly", "Monthly", "MonthlyRelative")) {
                $splatNewCalendarSchedule = @{
                    SqlInstance               = $TestConfig.InstanceSingle
                    Schedule                  = "dbatoolsci_$frequency"
                    Job                       = "dbatoolsci_setschedule2"
                    FrequencyType             = $frequency
                    FrequencyRecurrenceFactor = "1"
                    FrequencyInterval         = "1"
                    FrequencyRelativeInterval = "First"
                    StartDate                 = $start
                    StartTime                 = "010000"
                    EndDate                   = $end
                    EndTime                   = "020000"
                }

                $null = New-DbaAgentSchedule @splatNewCalendarSchedule
            }

            $schedules = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"

            foreach ($schedule in $schedules) {
                foreach ($frequency in ("Daily", "4", "Weekly", "8", "Monthly", "16", "MonthlyRelative", "32")) {
                    $splatSetCalendarSchedule = @{
                        SqlInstance               = $TestConfig.InstanceSingle
                        Schedule                  = "$($schedule.name)"
                        Job                       = "dbatoolsci_setschedule2"
                        FrequencyType             = $frequency
                        FrequencyRecurrenceFactor = 6
                        FrequencyInterval         = 4
                        FrequencyRelativeInterval = "Second"
                        StartDate                 = $altstart
                        StartTime                 = "113300"
                        EndDate                   = $altend
                        EndTime                   = "221100"
                    }

                    $null = Set-DbaAgentSchedule @splatSetCalendarSchedule
                }
            }

            $calendarFrequencyResults = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"
        }

        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Force
        }

        It "Should have Results" {
            $calendarFrequencyResults | Should -Not -BeNullOrEmpty
        }

        foreach ($r in $calendarFrequencyResults) {
            It "$($r.name) Should have a frequency of MonthlyRelative" {
                $r.FrequencyTypes | Should -Be "MonthlyRelative"
            }
            It "$($r.name) Should have different StartTime" {
                $r.StartTime | Should -Not -Be "$($schedules.where({$PSItem.id -eq $r.id}).StartTime)"
            }
        }
    }

    Context "Should set schedules with various frequency subday type" {
        BeforeAll {
            foreach ($FrequencySubdayType in ("Once", "Time", "Seconds", "Second", "Minutes", "Minute", "Hours", "Hour")) {
                $splatNewSubdaySchedule = @{
                    SqlInstance               = $TestConfig.InstanceSingle
                    Schedule                  = "dbatoolsci_$FrequencySubdayType"
                    Job                       = "dbatoolsci_setschedule1"
                    FrequencyRecurrenceFactor = "1"
                    FrequencySubdayInterval   = "5"
                    FrequencySubdayType       = $FrequencySubdayType
                    StartDate                 = $start
                    StartTime                 = "010000"
                    EndDate                   = $end
                    EndTime                   = "020000"
                }

                $null = New-DbaAgentSchedule @splatNewSubdaySchedule
            }

            $schedules = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"

            foreach ($schedule in $schedules) {
                foreach ($FrequencySubdayType in ("Once", "Time", "Seconds", "Second", "Minutes", "Minute", "Hours", "Hour")) {
                    $splatSetSubdaySchedule = @{
                        SqlInstance               = $TestConfig.InstanceSingle
                        Schedule                  = "$schedule"
                        Job                       = "dbatoolsci_setschedule1"
                        FrequencyRecurrenceFactor = "6"
                        FrequencySubdayInterval   = "4"
                        FrequencySubdayType       = $FrequencySubdayType
                        StartDate                 = $altstart
                        StartTime                 = "113300"
                        EndDate                   = $altend
                        EndTime                   = "221100"
                    }

                    $null = Set-DbaAgentSchedule @splatSetSubdaySchedule
                }
            }

            $subdayTypeResults = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"
        }

        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Force
        }

        It "Should have Results" {
            $subdayTypeResults | Should -Not -BeNullOrEmpty
        }

        foreach ($r in $subdayTypeResults) {
            It "$($r.name) Should have different EndDate" {
                $r.EndDate | Should -Not -Be "$($schedules.where({$PSItem.id -eq $r.id}).EndDate)"
            }
        }
    }

    Context "Should set schedules with various frequency relative interval" {
        BeforeAll {
            foreach ($FrequencyRelativeInterval in ("Unused", "First", "Second", "Third", "Fourth", "Last")) {
                $splatNewRelativeSchedule = @{
                    SqlInstance               = $TestConfig.InstanceSingle
                    Schedule                  = "dbatoolsci_$FrequencyRelativeInterval"
                    Job                       = "dbatoolsci_setschedule2"
                    FrequencyRecurrenceFactor = "1"
                    FrequencyRelativeInterval = $FrequencyRelativeInterval
                    StartDate                 = $start
                    StartTime                 = "010000"
                    EndDate                   = $end
                    EndTime                   = "020000"
                }

                $null = New-DbaAgentSchedule @splatNewRelativeSchedule
            }

            $schedules = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"

            foreach ($schedule in $schedules) {
                foreach ($FrequencyRelativeInterval in ("Unused", "First", "Second", "Third", "Fourth", "Last")) {
                    $splatSetRelativeSchedule = @{
                        SqlInstance               = $TestConfig.InstanceSingle
                        Schedule                  = "$schedule"
                        Job                       = "dbatoolsci_setschedule2"
                        FrequencyRecurrenceFactor = "4"
                        FrequencyRelativeInterval = $FrequencyRelativeInterval
                        StartDate                 = $altstart
                        StartTime                 = "113300"
                        EndDate                   = $altend
                        EndTime                   = "221100"
                    }

                    $null = Set-DbaAgentSchedule @splatSetRelativeSchedule
                }
            }

            $relativeIntervalResults = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"
        }

        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Force
        }

        It "Should have Results" {
            $relativeIntervalResults | Should -Not -BeNullOrEmpty
        }

        foreach ($r in $relativeIntervalResults) {
            It "$($r.name) Should have different EndTime" {
                $r.EndTime | Should -Not -Be "$($schedules.where({$PSItem.id -eq $r.id}).EndTime)"
            }
        }
    }
}