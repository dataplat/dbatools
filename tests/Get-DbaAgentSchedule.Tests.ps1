$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Schedule', 'ScheduleUid', 'Id', 'EnableException'
            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "UnitTests" {
    BeforeAll {
        Write-Message -Level Warning -Message "BeforeAll start: Get-DbaAgentSchedule.Tests.ps1 testing with instance3=$($script:instance3) and instance2=$($script:instance2)"
        $server3 = Connect-DbaInstance -SqlInstance $script:instance3
        $server2 = Connect-DbaInstance -SqlInstance $script:instance2

        $sqlAgentServer3 = Get-DbaService -ComputerName $server3.ComputerName -InstanceName $server3.DbaInstanceName -Type Agent
        Write-Message -Level Warning -Message "The SQL Agent service for instance3 has state=$($sqlAgentServer3.State) and start mode=$($sqlAgentServer3.StartMode)"

        $sqlAgentServer2 = Get-DbaService -ComputerName $server2.ComputerName -InstanceName $server2.DbaInstanceName -Type Agent
        Write-Message -Level Warning -Message "The SQL Agent service for instance2 has state=$($sqlAgentServer2.State) and start mode=$($sqlAgentServer2.StartMode)"

        $null = New-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_MonthlyTest -FrequencyType Monthly -FrequencyInterval 10 -FrequencyRecurrenceFactor 1 -Force
        $null = New-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_WeeklyTest -FrequencyType Weekly -FrequencyInterval 2 -FrequencyRecurrenceFactor 1 -StartTime 020000  -Force
        $null = New-DbaAgentSchedule -SqlInstance $script:instance3 -Schedule dbatoolsci_MonthlyTest -FrequencyType Monthly -FrequencyInterval 10 -FrequencyRecurrenceFactor 1 -Force
        $scheduleParams = @{
            SqlInstance               = $script:instance2
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
            SqlInstance               = $script:instance2
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
            SqlInstance               = $script:instance2
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
            SqlInstance               = $script:instance2
            Schedule                  = 'Issue_6636_Second'
            FrequencyInterval         = 1
            FrequencyRecurrenceFactor = 0
            FrequencySubdayInterval   = 10
            FrequencySubdayType       = 'Seconds'
            FrequencyType             = 'Daily'
            StartTime                 = '230000'
        }

        $null = New-DbaAgentSchedule @ScheduleParams -Force

        # frequency type additions for issue 6636
        $scheduleParams = @{
            SqlInstance   = $script:instance2
            Schedule      = "Issue_6636_OneTime"
            FrequencyType = "OneTime"
        }

        $null = New-DbaAgentSchedule @ScheduleParams -Force

        $scheduleParams = @{
            SqlInstance   = $script:instance2
            Schedule      = "Issue_6636_AutoStart"
            FrequencyType = "AutoStart"
        }

        $null = New-DbaAgentSchedule @ScheduleParams -Force

        $scheduleParams = @{
            SqlInstance   = $script:instance2
            Schedule      = "Issue_6636_OnIdle"
            FrequencyType = "OnIdle"
        }

        $null = New-DbaAgentSchedule @ScheduleParams -Force

        Write-Message -Level Warning -Message "BeforeAll end: Get-DbaAgentSchedule.Tests.ps1 testing with instance3=$($script:instance3) and instance2=$($script:instance2)"
    }
    AfterAll {
        Write-Message -Level Warning -Message "AfterAll start: Get-DbaAgentSchedule.Tests.ps1 testing with instance3=$($script:instance3) and instance2=$($script:instance2)"

        $schedules = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_WeeklyTest, dbatoolsci_MonthlyTest, Issue_6636_Once, Issue_6636_Once_Copy, Issue_6636_Hour, Issue_6636_Hour_Copy, Issue_6636_Minute, Issue_6636_Minute_Copy, Issue_6636_Second, Issue_6636_Second_Copy, Issue_6636_OneTime, Issue_6636_OneTime_Copy, Issue_6636_AutoStart, Issue_6636_AutoStart_Copy, Issue_6636_OnIdle, Issue_6636_OnIdle_Copy

        if ($null -ne $schedules) {
            $schedules.DROP()
        } else {
            Write-Message -Level Warning -Message "The schedules from $script:instance2 were returned as null"
        }

        $schedules = Get-DbaAgentSchedule -SqlInstance $script:instance3 -Schedule dbatoolsci_MonthlyTest

        if ($null -ne $schedules) {
            $schedules.DROP()
        } else {
            Write-Message -Level Warning -Message "The schedules from $script:instance3 were returned as null"
        }

        Write-Message -Level Warning -Message "AfterAll end: Get-DbaAgentSchedule.Tests.ps1 testing with instance3=$($script:instance3) and instance2=$($script:instance2)"
    }

    Context "Gets the list of Schedules" {
        It "Results are not empty" {
            $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_WeeklyTest, dbatoolsci_MonthlyTest
            $results.Count | Should -Be 2
        }
    }

    Context "Handles multiple instances" {
        It "Results contain two instances" {
            $results = Get-DbaAgentSchedule -SqlInstance $script:instance2, $script:instance3
            ($results | Select-Object SqlInstance -Unique).Count | Should -Be 2
        }
    }

    Context "Monthly schedule is correct" {
        It "verify schedule components" {
            $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_MonthlyTest

            $results.count                  | Should -Be 1
            $results                        | Should -Not -BeNullOrEmpty
            $results.ScheduleName           | Should -Be "dbatoolsci_MonthlyTest"
            $results.FrequencyInterval      | Should -Be 10
            $results.IsEnabled              | Should -Be $true
            $results.SqlInstance            | Should -Not -BeNullOrEmpty
            $datetimeFormat = (Get-Culture).DateTimeFormat
            $startDate = Get-Date $results.ActiveStartDate -Format $datetimeFormat.ShortDatePattern
            $startTime = Get-Date '00:00:00' -Format $datetimeFormat.LongTimePattern
            $results.Description            | Should -Be "Occurs every month on day 10 of that month at $startTime. Schedule will be used starting on $startDate."
        }
    }

    Context "Issue 6636 - provide flexibility in the FrequencySubdayType and FrequencyType input params based on the return values from the SMO object JobServer.SharedSchedules" {
        It "Ensure frequency subday type of 'Once' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_Once

            $scheduleParams = @{
                SqlInstance               = $script:instance2
                Schedule                  = 'Issue_6636_Once_Copy'
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubDayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes # "Once"
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_Once_Copy

            $result.ScheduleName            | Should -Be "Issue_6636_Once_Copy"
            $result.FrequencySubdayTypes    | Should -Be "Once"
        }

        It "Ensure frequency subday type of 'Hour' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_Hour

            $scheduleParams = @{
                SqlInstance               = $script:instance2
                Schedule                  = 'Issue_6636_Hour_Copy'
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubDayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes # "Hour"
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_Hour_Copy

            $result.ScheduleName            | Should -Be "Issue_6636_Hour_Copy"
            $result.FrequencySubdayTypes    | Should -Be "Hour"
        }

        It "Ensure frequency subday type of 'Minute' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_Minute

            $scheduleParams = @{
                SqlInstance               = $script:instance2
                Schedule                  = 'Issue_6636_Minute_Copy'
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubDayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes # "Minute"
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_Minute_Copy

            $result.ScheduleName            | Should -Be "Issue_6636_Minute_Copy"
            $result.FrequencySubdayTypes    | Should -Be "Minute"
        }

        It "Ensure frequency subday type of 'Second' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_Second

            $scheduleParams = @{
                SqlInstance               = $script:instance2
                Schedule                  = 'Issue_6636_Second_Copy'
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubDayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes # "Second"
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_Second_Copy

            $result.ScheduleName            | Should -Be "Issue_6636_Second_Copy"
            $result.FrequencySubdayTypes    | Should -Be "Second"
        }

        It "Ensure frequency type of 'OneTime' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_OneTime

            $scheduleParams = @{
                SqlInstance   = $script:instance2
                Schedule      = 'Issue_6636_OneTime_Copy'
                FrequencyType = $result.FrequencyTypes # OneTime
                StartTime     = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_OneTime_Copy

            $result.ScheduleName    | Should -Be "Issue_6636_OneTime_Copy"
            $result.FrequencyTypes  | Should -Be "OneTime"
        }

        It "Ensure frequency type of 'AutoStart' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_AutoStart

            $scheduleParams = @{
                SqlInstance   = $script:instance2
                Schedule      = 'Issue_6636_AutoStart_Copy'
                FrequencyType = $result.FrequencyTypes # AutoStart
                StartTime     = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_AutoStart_Copy

            $result.ScheduleName    | Should -Be "Issue_6636_AutoStart_Copy"
            $result.FrequencyTypes  | Should -Be "AutoStart"
        }

        It "Ensure frequency type of 'OnIdle' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_OnIdle

            $scheduleParams = @{
                SqlInstance   = $script:instance2
                Schedule      = 'Issue_6636_OnIdle_Copy'
                FrequencyType = $result.FrequencyTypes # OnIdle
            }

            $newSchedule = New-DbaAgentSchedule @ScheduleParams -Force

            $result = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule Issue_6636_OnIdle_Copy

            $result.ScheduleName    | Should -Be "Issue_6636_OnIdle_Copy"
            $result.FrequencyTypes  | Should -Be "OnIdle"
        }
    }
}