param($ModuleName = 'dbatools')

Describe "Get-DbaAgentSchedule Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Import module or set up environment as needed
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandName = Get-Command Get-DbaAgentSchedule
        }
        It "Should have the correct parameters" {
            $CommandName | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
            $CommandName | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
            $CommandName | Should -HaveParameter Schedule -Type String[] -Not -Mandatory
            $CommandName | Should -HaveParameter ScheduleUid -Type String[] -Not -Mandatory
            $CommandName | Should -HaveParameter Id -Type Int32[] -Not -Mandatory
            $CommandName | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

Describe "Get-DbaAgentSchedule Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $global:instance2 = $env:COMPUTERNAME
        $global:instance3 = $env:COMPUTERNAME

        $server2 = Connect-DbaInstance -SqlInstance $global:instance2
        $server3 = Connect-DbaInstance -SqlInstance $global:instance3

        $null = New-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule dbatoolsci_MonthlyTest -FrequencyType Monthly -FrequencyInterval 10 -FrequencyRecurrenceFactor 1 -Force
        $null = New-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule dbatoolsci_WeeklyTest -FrequencyType Weekly -FrequencyInterval 2 -FrequencyRecurrenceFactor 1 -StartTime 020000  -Force
        $null = New-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_MonthlyTest -FrequencyType Monthly -FrequencyInterval 10 -FrequencyRecurrenceFactor 1 -Force

        $scheduleParams = @{
            SqlInstance               = $global:instance2
            Schedule                  = 'Issue_6636_Once'
            FrequencyInterval         = 1
            FrequencyRecurrenceFactor = 0
            FrequencySubdayInterval   = 0
            FrequencySubdayType       = 'Time'
            FrequencyType             = 'Daily'
            StartTime                 = '230000'
        }
        $null = New-DbaAgentSchedule @ScheduleParams -Force

        $scheduleParams = @{
            SqlInstance               = $global:instance2
            Schedule                  = 'Issue_6636_Hour'
            FrequencyInterval         = 1
            FrequencyRecurrenceFactor = 0
            FrequencySubdayInterval   = 1
            FrequencySubdayType       = 'Hours'
            FrequencyType             = 'Daily'
            StartTime                 = '230000'
        }
        $null = New-DbaAgentSchedule @ScheduleParams -Force

        $scheduleParams = @{
            SqlInstance               = $global:instance2
            Schedule                  = 'Issue_6636_Minute'
            FrequencyInterval         = 1
            FrequencyRecurrenceFactor = 0
            FrequencySubdayInterval   = 30
            FrequencySubdayType       = 'Minutes'
            FrequencyType             = 'Daily'
            StartTime                 = '230000'
        }
        $null = New-DbaAgentSchedule @ScheduleParams -Force

        $scheduleParams = @{
            SqlInstance               = $global:instance2
            Schedule                  = 'Issue_6636_Second'
            FrequencyInterval         = 1
            FrequencyRecurrenceFactor = 0
            FrequencySubdayInterval   = 10
            FrequencySubdayType       = 'Seconds'
            FrequencyType             = 'Daily'
            StartTime                 = '230000'
        }
        $null = New-DbaAgentSchedule @ScheduleParams -Force

        $scheduleParams = @{
            SqlInstance   = $global:instance2
            Schedule      = "Issue_6636_OneTime"
            FrequencyType = "OneTime"
        }
        $null = New-DbaAgentSchedule @ScheduleParams -Force

        $scheduleParams = @{
            SqlInstance   = $global:instance2
            Schedule      = "Issue_6636_AutoStart"
            FrequencyType = "AutoStart"
        }
        $null = New-DbaAgentSchedule @ScheduleParams -Force

        $scheduleParams = @{
            SqlInstance   = $global:instance2
            Schedule      = "Issue_6636_OnIdle"
            FrequencyType = "OnIdle"
        }
        $null = New-DbaAgentSchedule @ScheduleParams -Force
    }

    AfterAll {
        $schedules = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule dbatoolsci_WeeklyTest, dbatoolsci_MonthlyTest, Issue_6636_Once, Issue_6636_Once_Copy, Issue_6636_Hour, Issue_6636_Hour_Copy, Issue_6636_Minute, Issue_6636_Minute_Copy, Issue_6636_Second, Issue_6636_Second_Copy, Issue_6636_OneTime, Issue_6636_OneTime_Copy, Issue_6636_AutoStart, Issue_6636_AutoStart_Copy, Issue_6636_OnIdle, Issue_6636_OnIdle_Copy
        if ($null -ne $schedules) {
            $schedules | ForEach-Object { $_.Drop() }
        }

        $schedules = Get-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_MonthlyTest
        if ($null -ne $schedules) {
            $schedules | ForEach-Object { $_.Drop() }
        }
    }

    Context "Gets the list of Schedules" {
        It "Results are not empty" {
            $results = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule dbatoolsci_WeeklyTest, dbatoolsci_MonthlyTest
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be 2
        }
    }

    Context "Handles multiple instances" {
        It "Results contain two instances" {
            $results = Get-DbaAgentSchedule -SqlInstance $global:instance2, $global:instance3
            ($results | Select-Object -Unique SqlInstance).Count | Should -Be 2
        }
    }

    Context "Monthly schedule is correct" {
        It "verify schedule components" {
            $results = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule dbatoolsci_MonthlyTest

            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be 1
            $results.ScheduleName | Should -Be "dbatoolsci_MonthlyTest"
            $results.FrequencyInterval | Should -Be 10
            $results.IsEnabled | Should -BeTrue
            $results.SqlInstance | Should -Not -BeNullOrEmpty

            $datetimeFormat = (Get-Culture).DateTimeFormat
            $startDate = Get-Date $results.ActiveStartDate -Format $datetimeFormat.ShortDatePattern
            $startTime = Get-Date '00:00:00' -Format $datetimeFormat.LongTimePattern
            $results.Description | Should -Be "Occurs every month on day 10 of that month at $startTime. Schedule will be used starting on $startDate."
        }
    }

    Context "Issue 6636 - provide flexibility in the FrequencySubdayType and FrequencyType input params" {
        It "Ensure frequency subday type of 'Once' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_Once

            $scheduleParams = @{
                SqlInstance               = $global:instance2
                Schedule                  = 'Issue_6636_Once_Copy'
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubDayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_Once_Copy

            $result.ScheduleName | Should -Be "Issue_6636_Once_Copy"
            $result.FrequencySubdayTypes | Should -Be "Once"
        }

        It "Ensure frequency subday type of 'Hour' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_Hour

            $scheduleParams = @{
                SqlInstance               = $global:instance2
                Schedule                  = 'Issue_6636_Hour_Copy'
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubDayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_Hour_Copy

            $result.ScheduleName | Should -Be "Issue_6636_Hour_Copy"
            $result.FrequencySubdayTypes | Should -Be "Hour"
        }

        It "Ensure frequency subday type of 'Minute' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_Minute

            $scheduleParams = @{
                SqlInstance               = $global:instance2
                Schedule                  = 'Issue_6636_Minute_Copy'
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubDayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_Minute_Copy

            $result.ScheduleName | Should -Be "Issue_6636_Minute_Copy"
            $result.FrequencySubdayTypes | Should -Be "Minute"
        }

        It "Ensure frequency subday type of 'Second' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_Second

            $scheduleParams = @{
                SqlInstance               = $global:instance2
                Schedule                  = 'Issue_6636_Second_Copy'
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubDayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_Second_Copy

            $result.ScheduleName | Should -Be "Issue_6636_Second_Copy"
            $result.FrequencySubdayTypes | Should -Be "Second"
        }

        It "Ensure frequency type of 'OneTime' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_OneTime

            $scheduleParams = @{
                SqlInstance   = $global:instance2
                Schedule      = 'Issue_6636_OneTime_Copy'
                FrequencyType = $result.FrequencyTypes
                StartTime     = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_OneTime_Copy

            $result.ScheduleName | Should -Be "Issue_6636_OneTime_Copy"
            $result.FrequencyTypes | Should -Be "OneTime"
        }

        It "Ensure frequency type of 'AutoStart' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_AutoStart

            $scheduleParams = @{
                SqlInstance   = $global:instance2
                Schedule      = 'Issue_6636_AutoStart_Copy'
                FrequencyType = $result.FrequencyTypes
                StartTime     = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_AutoStart_Copy

            $result.ScheduleName | Should -Be "Issue_6636_AutoStart_Copy"
            $result.FrequencyTypes | Should -Be "AutoStart"
        }

        It "Ensure frequency type of 'OnIdle' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_OnIdle

            $scheduleParams = @{
                SqlInstance   = $global:instance2
                Schedule      = 'Issue_6636_OnIdle_Copy'
                FrequencyType = $result.FrequencyTypes
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule Issue_6636_OnIdle_Copy

            $result.ScheduleName | Should -Be "Issue_6636_OnIdle_Copy"
            $result.FrequencyTypes | Should -Be "OnIdle"
        }
    }
}
