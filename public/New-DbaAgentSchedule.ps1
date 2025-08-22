function New-DbaAgentSchedule {
    <#
    .SYNOPSIS
        Creates a new SQL Server Agent schedule for automated job execution

    .DESCRIPTION
        Creates a new schedule in the msdb database that defines when SQL Server Agent jobs should execute. Schedules can be created as standalone objects or immediately attached to existing jobs, allowing you to standardize timing across multiple jobs without recreating the same schedule repeatedly. This replaces the need to manually create schedules through SQL Server Management Studio or T-SQL, while providing comprehensive validation of schedule parameters and frequency options. Supports all SQL Server Agent scheduling options including one-time, daily, weekly, monthly, and relative monthly frequencies with full control over start/end dates, times, and recurrence patterns.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job that has the schedule.

    .PARAMETER Schedule
        The name of the schedule.

    .PARAMETER Disabled
        Set the schedule to disabled. Default is enabled

    .PARAMETER FrequencyType
        A value indicating when a job is to be executed.

        Allowed values: 'Once', 'OneTime', 'Daily', 'Weekly', 'Monthly', 'MonthlyRelative', 'AgentStart', 'AutoStart', 'IdleComputer', 'OnIdle'

        The following synonyms provide flexibility to the allowed values for this function parameter:
        Once=OneTime
        AgentStart=AutoStart
        IdleComputer=OnIdle

        If force is used the default will be "Once".

    .PARAMETER FrequencyInterval
        The days that a job is executed

        Allowed values for FrequencyType 'Daily': EveryDay or a number between 1 and 365.
        Allowed values for FrequencyType 'Weekly': Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Weekdays, Weekend or EveryDay.
        Allowed values for FrequencyType 'Monthly': Numbers 1 to 31 for each day of the month.

        If "Weekdays", "Weekend" or "EveryDay" is used it over writes any other value that has been passed before.

        If force is used the default will be 1.

    .PARAMETER FrequencySubdayType
        Specifies the units for the subday FrequencyInterval.

        Allowed values: 'Once', 'Time', 'Seconds', 'Second', 'Minutes', 'Minute', 'Hours', 'Hour'

        The following synonyms provide flexibility to the allowed values for this function parameter:
        Once=Time
        Seconds=Second
        Minutes=Minute
        Hours=Hour

    .PARAMETER FrequencySubdayInterval
        The number of subday type periods to occur between each execution of a job.

        The interval needs to be at least 10 seconds long.

    .PARAMETER FrequencyRelativeInterval
        A job's occurrence of FrequencyInterval in each month, if FrequencyInterval is 32 (monthlyrelative).

        Allowed values: First, Second, Third, Fourth or Last

    .PARAMETER FrequencyRecurrenceFactor
        The number of weeks or months between the scheduled execution of a job.

        FrequencyRecurrenceFactor is used only if FrequencyType is "Weekly", "Monthly" or "MonthlyRelative".

    .PARAMETER StartDate
        The date on which execution of a job can begin. Must be a string in the format yyyyMMdd.

        If force is used the start date will be the current day

    .PARAMETER EndDate
        The date on which execution of a job can stop. Must be a string in the format yyyyMMdd.

        If force is used the end date will be '99991231'

    .PARAMETER StartTime
        The time on any day to begin execution of a job. Must be a string in the format HHmmss / 24 hour clock.
        Example: '010000' for 01:00:00 AM.
        Example: '140000' for 02:00:00 PM.

        If force is used the start time will be '000000' for midnight.

    .PARAMETER EndTime
        The time on any day to end execution of a job. Must be a string in the format HHmmss / 24 hour clock.
        Example: '010000' for 01:00:00 AM.
        Example: '140000' for 02:00:00 PM.

        If force is used the end time will be '235959' for one second before midnight.

    .PARAMETER Owner
        Login to own the job, defaults to login running the command.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.
        It will also remove the any present schedules with the same name for the specific job.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job, JobStep
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAgentSchedule

    .EXAMPLE
        PS C:\> New-DbaAgentSchedule -SqlInstance sql01 -Schedule DailyAt6 -FrequencyType Daily -StartTime "060000" -Force

        Creates a schedule that runs jobs every day at 6 in the morning. It assumes default values for the start date, start time, end date and end time due to -Force.

    .EXAMPLE
        PS C:\> New-DbaAgentSchedule -SqlInstance localhost\SQL2016 -Schedule daily -FrequencyType Daily -FrequencyInterval Everyday -Force

        Creates a schedule with a daily frequency every day. It assumes default values for the start date, start time, end date and end time due to -Force.

    .EXAMPLE
        PS C:\> New-DbaAgentSchedule -SqlInstance sstad-pc -Schedule MonthlyTest -FrequencyType Monthly -FrequencyInterval 10 -FrequencyRecurrenceFactor 1 -Force

        Create a schedule with a monthly frequency occuring every 10th of the month. It assumes default values for the start date, start time, end date and end time due to -Force.

    .EXAMPLE
        PS C:\> New-DbaAgentSchedule -SqlInstance sstad-pc -Schedule RunWeekly -FrequencyType Weekly -FrequencyInterval Sunday -StartTime 010000 -Force

        Create a schedule that will run jobs once a week on Sunday @ 1:00AM
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [object[]]$Job,
        [object]$Schedule,
        [switch]$Disabled,
        [ValidateSet('Once', 'OneTime', 'Daily', 'Weekly', 'Monthly', 'MonthlyRelative', 'AgentStart', 'AutoStart', 'IdleComputer', 'OnIdle')]
        [object]$FrequencyType,
        [object[]]$FrequencyInterval,
        [ValidateSet('Once', 'Time', 'Seconds', 'Second', 'Minutes', 'Minute', 'Hours', 'Hour')]
        [object]$FrequencySubdayType,
        [int]$FrequencySubdayInterval,
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$FrequencyRelativeInterval,
        [int]$FrequencyRecurrenceFactor,
        [string]$StartDate,
        [string]$EndDate,
        [string]$StartTime,
        [string]$EndTime,
        [string]$Owner,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if ($FrequencyType -eq "Daily" -and -not $FrequencyInterval) {
            $FrequencyInterval = 1
        }

        # if a Schedule is not provided there is no much point
        if (-not $Schedule) {
            Stop-Function -Message "A schedule was not provided! Please provide a schedule name."
            return
        }

        [int]$interval = 0

        # Translate FrequencyType value from string to the integer value
        [int]$FrequencyType =
        switch ($FrequencyType) {
            "Once" { 1 }
            "OneTime" { 1 }
            "Daily" { 4 }
            "Weekly" { 8 }
            "Monthly" { 16 }
            "MonthlyRelative" { 32 }
            "AgentStart" { 64 }
            "AutoStart" { 64 }
            "IdleComputer" { 128 }
            "OnIdle" { 128 }
            default { 1 }
        }

        # Translate FrequencySubdayType value from string to the integer value
        [int]$FrequencySubdayType =
        switch ($FrequencySubdayType) {
            "Once" { 1 }
            "Time" { 1 }
            "Seconds" { 2 }
            "Second" { 2 }
            "Minutes" { 4 }
            "Minute" { 4 }
            "Hours" { 8 }
            "Hour" { 8 }
            default { 1 }
        }

        # Check if the relative FrequencyInterval value is of type string and set the integer value
        [int]$FrequencyRelativeInterval =
        switch ($FrequencyRelativeInterval) {
            "First" { 1 }
            "Second" { 2 }
            "Third" { 4 }
            "Fourth" { 8 }
            "Last" { 16 }
            "Unused" { 0 }
            default { 0 }
        }

        # Check if the interval for daily frequency is valid
        if (($FrequencyType -eq 4) -and ($FrequencyInterval -lt 1 -or $FrequencyInterval -ge 365) -and (-not ($FrequencyInterval -eq "EveryDay")) -and (-not $Force)) {
            Stop-Function -Message "The daily frequency type requires a frequency interval to be between 1 and 365 or 'EveryDay'." -Target $SqlInstance
            return
        }

        # Check if the recurrence factor is set for weekly or monthly interval
        if (($FrequencyType -in (16, 8)) -and $FrequencyRecurrenceFactor -lt 1) {
            if ($Force) {
                $FrequencyRecurrenceFactor = 1
                Write-Message -Message "Recurrence factor not set for weekly or monthly interval. Setting it to $FrequencyRecurrenceFactor." -Level Verbose
            } else {
                Stop-Function -Message "The recurrence factor $FrequencyRecurrenceFactor (parameter FrequencyRecurrenceFactor) needs to be at least one when using a weekly or monthly interval." -Target $SqlInstance
                return
            }
        }

        # Check the subday interval
        if (($FrequencySubdayType -in 2, "Seconds") -and (-not ($FrequencySubdayInterval -ge 10 -or $FrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 10 and 59 when subday type is 'Seconds'" -Target $SqlInstance
            return
        } elseif (($FrequencySubdayType -in 4, "Minutes") -and (-not ($FrequencySubdayInterval -ge 1 -or $FrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 59 when subday type is 'Minutes'" -Target $SqlInstance
            return
        } elseif (($FrequencySubdayType -eq 8, "Hours") -and (-not ($FrequencySubdayInterval -ge 1 -and $FrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 23 when subday type is 'Hours'" -Target $SqlInstance
            return
        }

        # If the FrequencyInterval is set for the daily FrequencyType
        if ($FrequencyType -eq 4) {
            # Create the interval to hold the value(s)
            [int]$interval = 1

            if ($FrequencyInterval -and $FrequencyInterval[0].GetType().Name -eq 'Int32') {
                $interval = $FrequencyInterval[0]
            }
        }

        # If the FrequencyInterval is set for the weekly FrequencyType
        if ($FrequencyType -in 8, 'Weekly') {
            # Create the interval to hold the value(s)
            [int]$interval = 0

            # Loop through the array
            foreach ($item in $FrequencyInterval) {

                switch ($item) {
                    "Sunday" { $interval += 1 }
                    "Monday" { $interval += 2 }
                    "Tuesday" { $interval += 4 }
                    "Wednesday" { $interval += 8 }
                    "Thursday" { $interval += 16 }
                    "Friday" { $interval += 32 }
                    "Saturday" { $interval += 64 }
                    "Weekdays" { $interval = 62 }
                    "Weekend" { $interval = 65 }
                    "EveryDay" { $interval = 127 }
                    1 { $interval += 1 }
                    2 { $interval += 2 }
                    4 { $interval += 4 }
                    8 { $interval += 8 }
                    16 { $interval += 16 }
                    32 { $interval += 32 }
                    64 { $interval += 64 }
                    62 { $interval = 62 }
                    65 { $interval = 65 }
                    120 { $interval = 120 }
                    121 { $interval = 121 }
                    122 { $interval = 122 }
                    123 { $interval = 123 }
                    124 { $interval = 124 }
                    125 { $interval = 125 }
                    126 { $interval = 126 }
                    127 { $interval = 127 }
                    default { $interval = 0 }
                }
            }
        }

        # If the FrequencyInterval is set for the monthly FrequencyInterval
        if ($FrequencyType -in 16, 'Monthly') {
            # Create the interval to hold the value(s)
            [int]$interval = 0

            # Loop through the array
            foreach ($item in $FrequencyInterval) {
                switch ($item) {
                    { [int]$_ -ge 1 -and [int]$_ -le 31 } { $interval = [int]$item }
                }
            }
        }

        # If the FrequencyInterval is set for the relative monthly FrequencyInterval
        if ($FrequencyType -eq 32) {
            # Create the interval to hold the value(s)
            [int]$interval = 0

            # Loop through the array
            foreach ($item in $FrequencyInterval) {
                switch ($item) {
                    "Sunday" { $interval += 1 }
                    "Monday" { $interval += 2 }
                    "Tuesday" { $interval += 3 }
                    "Wednesday" { $interval += 4 }
                    "Thursday" { $interval += 5 }
                    "Friday" { $interval += 6 }
                    "Saturday" { $interval += 7 }
                    "Day" { $interval += 8 }
                    "Weekdays" { $interval += 9 }
                    "WeekendDay" { $interval += 10 }
                    1 { $interval += 1 }
                    2 { $interval += 2 }
                    3 { $interval += 3 }
                    4 { $interval += 4 }
                    5 { $interval += 5 }
                    6 { $interval += 6 }
                    7 { $interval += 7 }
                    8 { $interval += 8 }
                    9 { $interval += 9 }
                    10 { $interval += 10 }
                }
            }
        }

        # Check if the interval is valid for the frequency
        if ($FrequencyType -eq 0) {
            if ($Force) {
                Write-Message -Message "Parameter FrequencyType must be set to at least [Once]. Setting it to 'Once'." -Level Warning
                $FrequencyType = 1
            } else {
                Stop-Function -Message "Parameter FrequencyType must be set to at least [Once]" -Target $SqlInstance
                return
            }
        }

        # Check if the interval is valid for the frequency
        if (($FrequencyType -in 4, 8, 32) -and ($interval -lt 1)) {
            if ($Force) {
                Write-Message -Message "Parameter FrequencyInterval must be provided for a recurring schedule. Setting it to first day of the week." -Level Warning
                $interval = 1
            } else {
                Stop-Function -Message "Parameter FrequencyInterval must be provided for a recurring schedule." -Target $SqlInstance
                return
            }
        }

        # Check the start date
        if (-not $StartDate -and $Force) {
            $StartDate = Get-Date -Format 'yyyyMMdd'
            Write-Message -Message "Start date was not set. Force is being used. Setting it to $StartDate" -Level Verbose
        } elseif (-not $StartDate) {
            Stop-Function -Message "Please enter a start date or use -Force to use defaults." -Target $SqlInstance
            return
        }
        try {
            $activeStartDate = New-Object System.DateTime($StartDate.Substring(0, 4), $StartDate.Substring(4, 2), $StartDate.Substring(6, 2))
        } catch {
            Stop-Function -Message "Start date $StartDate needs to be a valid date with format yyyyMMdd." -Target $SqlInstance
            return
        }

        # Check the end date
        if (-not $EndDate -and $Force) {
            $EndDate = '99991231'
            Write-Message -Message "End date was not set. Force is being used. Setting it to $EndDate" -Level Verbose
        } elseif (-not $EndDate) {
            Stop-Function -Message "Please enter an end date or use -Force to use defaults." -Target $SqlInstance
            return
        }
        try {
            $activeEndDate = New-Object System.DateTime($EndDate.Substring(0, 4), $EndDate.Substring(4, 2), $EndDate.Substring(6, 2))
        } catch {
            Stop-Function -Message "End date $EndDate needs to be a valid date with format yyyyMMdd." -Target $SqlInstance
            return
        }
        if ($activeEndDate -lt $activeStartDate) {
            Stop-Function -Message "End date $EndDate cannot be before start date $StartDate." -Target $SqlInstance
            return
        }

        # Check the start time
        if (-not $StartTime -and $Force) {
            $StartTime = '000000'
            Write-Message -Message "Start time was not set. Force is being used. Setting it to $StartTime" -Level Verbose
        } elseif (-not $StartTime) {
            Stop-Function -Message "Please enter a start time or use -Force to use defaults." -Target $SqlInstance
            return
        }
        try {
            $activeStartTimeOfDay = New-Object System.TimeSpan($StartTime.Substring(0, 2), $StartTime.Substring(2, 2), $StartTime.Substring(4, 2))
        } catch {
            Stop-Function -Message "Start time $StartTime needs to be a valid time with format HHmmss." -Target $SqlInstance
            return
        }

        # Check the end time
        if (-not $EndTime -and $Force) {
            $EndTime = '235959'
            Write-Message -Message "End time was not set. Force is being used. Setting it to $EndTime" -Level Verbose
        } elseif (-not $EndTime) {
            Stop-Function -Message "Please enter an end time or use -Force to use defaults." -Target $SqlInstance
            return
        }
        try {
            $activeEndTimeOfDay = New-Object System.TimeSpan($EndTime.Substring(0, 2), $EndTime.Substring(2, 2), $EndTime.Substring(4, 2))
        } catch {
            Stop-Function -Message "End time $EndTime needs to be a valid time with format HHmmss." -Target $SqlInstance
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            # Create the schedule
            if ($PSCmdlet.ShouldProcess($instance, "Adding the schedule $schedule")) {
                try {
                    Write-Message -Message "Adding the schedule $jobschedule on instance $instance" -Level Verbose

                    # Create the schedule
                    $jobschedule = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobSchedule($Server.JobServer, $Schedule)

                    #region job schedule options
                    if ($Disabled) {
                        Write-Message -Message "Setting job schedule to disabled" -Level Verbose
                        $jobschedule.IsEnabled = $false
                    } else {
                        Write-Message -Message "Setting job schedule to enabled" -Level Verbose
                        $jobschedule.IsEnabled = $true
                    }

                    if ($interval -ge 1) {
                        Write-Message -Message "Setting job schedule frequency interval to $interval" -Level Verbose
                        $jobschedule.FrequencyInterval = $interval
                    }

                    if ($FrequencyType -ge 1) {
                        Write-Message -Message "Setting job schedule frequency to $FrequencyType" -Level Verbose
                        $jobschedule.FrequencyTypes = $FrequencyType
                    }

                    if ($FrequencySubdayType -ge 1) {
                        Write-Message -Message "Setting job schedule frequency subday type to $FrequencySubdayType" -Level Verbose
                        $jobschedule.FrequencySubDayTypes = $FrequencySubdayType
                    }

                    if ($FrequencySubdayInterval -ge 1) {
                        Write-Message -Message "Setting job schedule frequency subday interval to $FrequencySubdayInterval" -Level Verbose
                        $jobschedule.FrequencySubDayInterval = $FrequencySubdayInterval
                    }

                    if (($FrequencyRelativeInterval -ge 1) -and ($FrequencyType -eq 32)) {
                        Write-Message -Message "Setting job schedule frequency relative interval to $FrequencyRelativeInterval" -Level Verbose
                        $jobschedule.FrequencyRelativeIntervals = $FrequencyRelativeInterval
                    }

                    if (($FrequencyRecurrenceFactor -ge 1) -and ($FrequencyType -in 8, 16, 32)) {
                        Write-Message -Message "Setting job schedule frequency recurrence factor to $FrequencyRecurrenceFactor" -Level Verbose
                        $jobschedule.FrequencyRecurrenceFactor = $FrequencyRecurrenceFactor
                    }

                    Write-Message -Message "Setting job schedule start date to $StartDate / $activeStartDate" -Level Verbose
                    $jobschedule.ActiveStartDate = $activeStartDate

                    Write-Message -Message "Setting job schedule end date to $EndDate / $activeEndDate" -Level Verbose
                    $jobschedule.ActiveEndDate = $activeEndDate

                    Write-Message -Message "Setting job schedule start time to $StartTime / $activeStartTimeOfDay" -Level Verbose
                    $jobschedule.ActiveStartTimeOfDay = $activeStartTimeOfDay

                    Write-Message -Message "Setting job schedule end time to $EndTime / $activeEndTimeOfDay" -Level Verbose
                    $jobschedule.ActiveEndTimeOfDay = $activeEndTimeOfDay

                    if ($Owner) {
                        $jobschedule.OwnerLoginName = $Owner
                    }

                    $jobschedule.Create()

                    Write-Message -Message "Job schedule created with UID $($jobschedule.ScheduleUid)" -Level Verbose
                } catch {
                    Stop-Function -Message "Something went wrong adding the schedule." -Target $instance -ErrorRecord $_ -Continue
                }
                $null = $server.Refresh()
                $null = $server.JobServer.Refresh()
                Add-TeppCacheItem -SqlInstance $server -Type schedule -Name $Schedule
            }
            if ($Job) {
                $jobs = Get-DbaAgentJob -SqlInstance $server -Job $Job
                foreach ($j in $jobs) {
                    if ($PSCmdlet.ShouldProcess($instance, "Adding the schedule $schedule to job $($j.Name)")) {
                        Write-Message -Message "Adding schedule $Schedule to job $($j.Name)" -Level Verbose
                        $j.AddSharedSchedule($jobschedule.Id)
                        $jobschedule.Refresh()
                    }
                }
            }
            # Output the job schedule
            if ($jobschedule) {
                Get-DbaAgentSchedule -SqlInstance $server -ScheduleUid $jobschedule.ScheduleUid
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished creating job schedule(s)." -Level Verbose
    }
}