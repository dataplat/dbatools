#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentSchedule",
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
                "Schedule",
                "ScheduleUid",
                "Id",
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

        $null = New-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule dbatoolsci_MonthlyTest -FrequencyType Monthly -FrequencyInterval 10 -FrequencyRecurrenceFactor 1 -Force
        $null = New-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule dbatoolsci_WeeklyTest -FrequencyType Weekly -FrequencyInterval 2 -FrequencyRecurrenceFactor 1 -StartTime 020000 -Force
        $null = New-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti2 -Schedule dbatoolsci_MonthlyTest -FrequencyType Monthly -FrequencyInterval 10 -FrequencyRecurrenceFactor 1 -Force

        $splatScheduleOnce = @{
            SqlInstance               = $TestConfig.InstanceMulti1
            Schedule                  = "Issue_6636_Once"
            FrequencyInterval         = 1
            FrequencyRecurrenceFactor = 0
            FrequencySubdayInterval   = 0
            FrequencySubdayType       = "Time"
            FrequencyType             = "Daily"
            StartTime                 = "230000"
        }

        $null = New-DbaAgentSchedule @splatScheduleOnce -Force

        $splatScheduleHour = @{
            SqlInstance               = $TestConfig.InstanceMulti1
            Schedule                  = "Issue_6636_Hour"
            FrequencyInterval         = 1
            FrequencyRecurrenceFactor = 0
            FrequencySubdayInterval   = 1
            FrequencySubdayType       = "Hours"
            FrequencyType             = "Daily"
            StartTime                 = "230000"
        }

        $null = New-DbaAgentSchedule @splatScheduleHour -Force

        $splatScheduleMinute = @{
            SqlInstance               = $TestConfig.InstanceMulti1
            Schedule                  = "Issue_6636_Minute"
            FrequencyInterval         = 1
            FrequencyRecurrenceFactor = 0
            FrequencySubdayInterval   = 30
            FrequencySubdayType       = "Minutes"
            FrequencyType             = "Daily"
            StartTime                 = "230000"
        }

        $null = New-DbaAgentSchedule @splatScheduleMinute -Force

        $splatScheduleSecond = @{
            SqlInstance               = $TestConfig.InstanceMulti1
            Schedule                  = "Issue_6636_Second"
            FrequencyInterval         = 1
            FrequencyRecurrenceFactor = 0
            FrequencySubdayInterval   = 10
            FrequencySubdayType       = "Seconds"
            FrequencyType             = "Daily"
            StartTime                 = "230000"
        }

        $null = New-DbaAgentSchedule @splatScheduleSecond -Force

        # frequency type additions for issue 6636
        $splatScheduleOneTime = @{
            SqlInstance   = $TestConfig.InstanceMulti1
            Schedule      = "Issue_6636_OneTime"
            FrequencyType = "OneTime"
        }

        $null = New-DbaAgentSchedule @splatScheduleOneTime -Force

        $splatScheduleAutoStart = @{
            SqlInstance   = $TestConfig.InstanceMulti1
            Schedule      = "Issue_6636_AutoStart"
            FrequencyType = "AutoStart"
        }

        $null = New-DbaAgentSchedule @splatScheduleAutoStart -Force

        $splatScheduleOnIdle = @{
            SqlInstance   = $TestConfig.InstanceMulti1
            Schedule      = "Issue_6636_OnIdle"
            FrequencyType = "OnIdle"
        }

        $null = New-DbaAgentSchedule @splatScheduleOnIdle -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $schedulesToRemove = @(
            "dbatoolsci_WeeklyTest",
            "dbatoolsci_MonthlyTest",
            "Issue_6636_Once",
            "Issue_6636_Once_Copy",
            "Issue_6636_Hour",
            "Issue_6636_Hour_Copy",
            "Issue_6636_Minute",
            "Issue_6636_Minute_Copy",
            "Issue_6636_Second",
            "Issue_6636_Second_Copy",
            "Issue_6636_OneTime",
            "Issue_6636_OneTime_Copy",
            "Issue_6636_AutoStart",
            "Issue_6636_AutoStart_Copy",
            "Issue_6636_OnIdle",
            "Issue_6636_OnIdle_Copy"
        )

        $schedules = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule $schedulesToRemove

        if ($null -ne $schedules) {
            $schedules.DROP()
        }

        $schedules = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti2 -Schedule dbatoolsci_MonthlyTest

        if ($null -ne $schedules) {
            $schedules.DROP()
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets the list of Schedules" {
        It "Results are not empty" {
            $results = @(Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule dbatoolsci_WeeklyTest, dbatoolsci_MonthlyTest)
            $results.Count | Should -Be 2
        }
    }

    Context "Handles multiple instances" {
        It "Results contain two instances" {
            $results = @(Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2)
            ($results | Select-Object SqlInstance -Unique).Count | Should -Be 2
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule dbatoolsci_MonthlyTest -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.JobSchedule]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'ScheduleName',
                'ActiveEndDate',
                'ActiveEndTimeOfDay',
                'ActiveStartDate',
                'ActiveStartTimeOfDay',
                'DateCreated',
                'FrequencyInterval',
                'FrequencyRecurrenceFactor',
                'FrequencyRelativeIntervals',
                'FrequencySubDayInterval',
                'FrequencySubDayTypes',
                'FrequencyTypes',
                'IsEnabled',
                'JobCount',
                'Description',
                'ScheduleUid'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Monthly schedule is correct" {
        It "verify schedule components" {
            $results = @(Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule dbatoolsci_MonthlyTest)

            $results.Count | Should -Be 1
            $results | Should -Not -BeNullOrEmpty
            $results.ScheduleName | Should -Be "dbatoolsci_MonthlyTest"
            $results.FrequencyInterval | Should -Be 10
            $results.IsEnabled | Should -Be $true
            $results.SqlInstance | Should -Not -BeNullOrEmpty
            $datetimeFormat = (Get-Culture).DateTimeFormat
            $startDate = Get-Date $results.ActiveStartDate -Format $datetimeFormat.ShortDatePattern
            $startTime = Get-Date "00:00:00" -Format $datetimeFormat.LongTimePattern
            $results.Description | Should -Be "Occurs every month on day 10 of that month at $startTime. Schedule will be used starting on $startDate."
        }
    }

    Context "Issue 6636 - provide flexibility in the FrequencySubdayType and FrequencyType input params based on the return values from the SMO object JobServer.SharedSchedules" {
        It "Ensure frequency subday type of 'Once' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_Once

            $splatCopyOnce = @{
                SqlInstance               = $TestConfig.InstanceMulti1
                Schedule                  = "Issue_6636_Once_Copy"
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubDayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes # "Once"
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @splatCopyOnce -Force

            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_Once_Copy

            $result.ScheduleName | Should -Be "Issue_6636_Once_Copy"
            $result.FrequencySubdayTypes | Should -Be "Once"
        }

        It "Ensure frequency subday type of 'Hour' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_Hour

            $splatCopyHour = @{
                SqlInstance               = $TestConfig.InstanceMulti1
                Schedule                  = "Issue_6636_Hour_Copy"
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubdayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes # "Hour"
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @splatCopyHour -Force

            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_Hour_Copy

            $result.ScheduleName | Should -Be "Issue_6636_Hour_Copy"
            $result.FrequencySubdayTypes | Should -Be "Hour"
        }

        It "Ensure frequency subday type of 'Minute' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_Minute

            $splatCopyMinute = @{
                SqlInstance               = $TestConfig.InstanceMulti1
                Schedule                  = "Issue_6636_Minute_Copy"
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubdayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes # "Minute"
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @splatCopyMinute -Force

            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_Minute_Copy

            $result.ScheduleName | Should -Be "Issue_6636_Minute_Copy"
            $result.FrequencySubdayTypes | Should -Be "Minute"
        }

        It "Ensure frequency subday type of 'Second' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_Second

            $splatCopySecond = @{
                SqlInstance               = $TestConfig.InstanceMulti1
                Schedule                  = "Issue_6636_Second_Copy"
                FrequencyInterval         = $result.FrequencyInterval
                FrequencyRecurrenceFactor = $result.FrequencyRecurrenceFactor
                FrequencySubdayInterval   = $result.FrequencySubdayInterval
                FrequencySubdayType       = $result.FrequencySubdayTypes # "Second"
                FrequencyType             = $result.FrequencyTypes
                StartTime                 = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @splatCopySecond -Force

            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_Second_Copy

            $result.ScheduleName | Should -Be "Issue_6636_Second_Copy"
            $result.FrequencySubdayTypes | Should -Be "Second"
        }

        It "Ensure frequency type of 'OneTime' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_OneTime

            $splatCopyOneTime = @{
                SqlInstance   = $TestConfig.InstanceMulti1
                Schedule      = "Issue_6636_OneTime_Copy"
                FrequencyType = $result.FrequencyTypes # OneTime
                StartTime     = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @splatCopyOneTime -Force

            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_OneTime_Copy

            $result.ScheduleName | Should -Be "Issue_6636_OneTime_Copy"
            $result.FrequencyTypes | Should -Be "OneTime"
        }

        It "Ensure frequency type of 'AutoStart' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_AutoStart

            $splatCopyAutoStart = @{
                SqlInstance   = $TestConfig.InstanceMulti1
                Schedule      = "Issue_6636_AutoStart_Copy"
                FrequencyType = $result.FrequencyTypes # AutoStart
                StartTime     = $result.ActiveStartTimeOfDay.ToString().Replace(":", "")
            }

            $newSchedule = New-DbaAgentSchedule @splatCopyAutoStart -Force

            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_AutoStart_Copy

            $result.ScheduleName | Should -Be "Issue_6636_AutoStart_Copy"
            $result.FrequencyTypes | Should -Be "AutoStart"
        }

        It "Ensure frequency type of 'OnIdle' is usable" {
            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_OnIdle

            $splatCopyOnIdle = @{
                SqlInstance   = $TestConfig.InstanceMulti1
                Schedule      = "Issue_6636_OnIdle_Copy"
                FrequencyType = $result.FrequencyTypes # OnIdle
            }

            $newSchedule = New-DbaAgentSchedule @splatCopyOnIdle -Force

            $result = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceMulti1 -Schedule Issue_6636_OnIdle_Copy

            $result.ScheduleName | Should -Be "Issue_6636_OnIdle_Copy"
            $result.FrequencyTypes | Should -Be "OnIdle"
        }
    }
}