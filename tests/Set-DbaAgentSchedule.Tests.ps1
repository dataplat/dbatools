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

        # The results only exist once the setup has talked to the instance, so there is nothing to
        # hand to -ForEach at discovery time and the loop has to live inside the It block. Written
        # as a foreach around the It, as it was before, the loop ran while Pester was still
        # discovering the tests, $renameScheduleResults was empty and no test was created at all.
        It "Should have renamed every schedule" {
            foreach ($r in $renameScheduleResults) {
                $r.name | Should -Not -Be "$($schedules.where({$PSItem.id -eq $r.id}).name)" -Because "schedule $($r.id) should have been renamed"
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

        It "Should have a frequency of OnIdle on every schedule" {
            foreach ($r in $staticFrequencyResults) {
                $r.FrequencyTypes | Should -Be "OnIdle" -Because "schedule $($r.name) was last set to IdleComputer"
            }
        }

        It "Should have every schedule Enabled" {
            foreach ($r in $staticFrequencyResults) {
                $r.isEnabled | Should -Be "True" -Because "schedule $($r.name) was last set with Enabled"
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

        It "Should have a frequency of MonthlyRelative on every schedule" {
            foreach ($r in $calendarFrequencyResults) {
                $r.FrequencyTypes | Should -Be "MonthlyRelative" -Because "schedule $($r.name) was last set to MonthlyRelative"
            }
        }

        It "Should have a different StartTime on every schedule" {
            foreach ($r in $calendarFrequencyResults) {
                $r.StartTime | Should -Not -Be "$($schedules.where({$PSItem.id -eq $r.id}).StartTime)" -Because "schedule $($r.name) was given a new StartTime"
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

        It "Should have a different EndDate on every schedule" {
            foreach ($r in $subdayTypeResults) {
                $r.EndDate | Should -Not -Be "$($schedules.where({$PSItem.id -eq $r.id}).EndDate)" -Because "schedule $($r.name) was given a new EndDate"
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

        It "Should have a different EndTime on every schedule" {
            foreach ($r in $relativeIntervalResults) {
                $r.EndTime | Should -Not -Be "$($schedules.where({$PSItem.id -eq $r.id}).EndTime)" -Because "schedule $($r.name) was given a new EndTime"
            }
        }
    }

    Context "Should keep the frequency settings when they are not part of the change" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatNewKeepSchedule = @{
                SqlInstance             = $TestConfig.InstanceSingle
                Schedule                = "dbatoolsci_keepfrequency"
                Job                     = "dbatoolsci_setschedule1"
                FrequencyType           = "Daily"
                FrequencyInterval       = "EveryDay"
                FrequencySubdayType     = "Hours"
                FrequencySubdayInterval = 4
                StartTime               = "060000"
                Force                   = $true
            }
            $null = New-DbaAgentSchedule @splatNewKeepSchedule

            # Changing only the start time must not touch the recurrence (#10461)
            $splatSetStartTime = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = "dbatoolsci_setschedule1"
                Schedule    = "dbatoolsci_keepfrequency"
                StartTime   = "235900"
            }
            $null = Set-DbaAgentSchedule @splatSetStartTime
            $startTimeResult = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule "dbatoolsci_keepfrequency"

            # The same is true for a call that only enables the schedule
            $splatSetEnabled = @{
                SqlInstance = $TestConfig.InstanceSingle
                Job         = "dbatoolsci_setschedule1"
                Schedule    = "dbatoolsci_keepfrequency"
                Enabled     = $true
            }
            $null = Set-DbaAgentSchedule @splatSetEnabled
            $enabledResult = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule "dbatoolsci_keepfrequency"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Force

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have changed the start time" {
            $startTimeResult.ActiveStartTimeOfDay | Should -Be ([TimeSpan]"23:59:00")
        }

        It "Should have kept the frequency settings after changing the start time" {
            $startTimeResult.FrequencyTypes | Should -Be "Daily"
            $startTimeResult.FrequencyInterval | Should -Be 1
            $startTimeResult.FrequencySubDayTypes | Should -Be "Hour"
            $startTimeResult.FrequencySubDayInterval | Should -Be 4
        }

        It "Should have kept the frequency settings after enabling the schedule" {
            $enabledResult.IsEnabled | Should -BeTrue
            $enabledResult.FrequencyTypes | Should -Be "Daily"
            $enabledResult.FrequencyInterval | Should -Be 1
            $enabledResult.FrequencySubDayTypes | Should -Be "Hour"
            $enabledResult.FrequencySubDayInterval | Should -Be 4
        }
    }
}