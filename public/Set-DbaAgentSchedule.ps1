function Set-DbaAgentSchedule {
    <#
    .SYNOPSIS
        Modifies properties of existing SQL Agent job schedules

    .DESCRIPTION
        Modifies the timing, frequency, and other properties of existing SQL Agent job schedules without recreating them. You can update schedule frequency (daily, weekly, monthly), change start/end times and dates, enable or disable schedules, and rename them. The function works with schedules already attached to jobs and validates all timing parameters to prevent invalid configurations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies the name of the SQL Agent job that contains the schedule to modify. You can provide multiple job names to update schedules across different jobs.
        Use this when you need to change schedule properties for specific jobs without affecting other jobs that might share the same schedule name.

    .PARAMETER ScheduleName
        Specifies the name of the existing schedule to modify within the specified job. Schedule names are case-sensitive.
        Use this to target the specific schedule when a job has multiple schedules attached to it.

    .PARAMETER NewName
        Renames the schedule to the specified new name. The new name must be unique within the job's schedules.
        Use this when you need to rename schedules for better organization or to follow naming conventions.

    .PARAMETER Enabled
        Activates the schedule so the job will run according to its configured timing. This overrides any disabled state.
        Use this to reactivate schedules that were previously disabled without changing their timing configuration.

    .PARAMETER Disabled
        Deactivates the schedule so the job will not run, even if it meets the timing criteria. The schedule configuration remains unchanged.
        Use this to temporarily stop jobs without deleting their schedules during maintenance windows or troubleshooting.

    .PARAMETER FrequencyType
        Sets the overall pattern for when the job should execute. This is the primary schedule type that determines how often the job runs.
        Use 'Daily' for jobs that run every day or every few days, 'Weekly' for jobs on specific weekdays, 'Monthly' for jobs on specific dates, 'MonthlyRelative' for jobs like "first Monday of the month", 'Once' for one-time execution, 'AgentStart' to run when SQL Agent starts, or 'OnIdle' when server is idle.
        This parameter works with FrequencyInterval to create the complete schedule pattern.

    .PARAMETER FrequencyInterval
        Specifies which days or intervals the job should run based on the FrequencyType. The values depend on the schedule type you choose.
        For 'Daily': Use a number (1-365) for every N days or 'EveryDay'. For 'Weekly': Use day names like Monday, Tuesday or shortcuts like 'Weekdays', 'Weekend'. For 'Monthly': Use day numbers 1-31. For 'MonthlyRelative': Use day names for "first Monday" type schedules.
        This parameter works together with FrequencyType to define the exact timing pattern for your job schedule.

    .PARAMETER FrequencySubdayType
        Defines the unit of time for running jobs multiple times within a single day. This controls what the FrequencySubdayInterval value represents.
        Use 'Once' for jobs that run only once per day, 'Hours' for jobs that repeat every few hours, 'Minutes' for jobs that run every few minutes, or 'Seconds' for very frequent execution.
        This parameter is only relevant when you need jobs to execute more than once per day at regular intervals.

    .PARAMETER FrequencySubdayInterval
        Specifies how many units of the FrequencySubdayType to wait between job executions within a day. For example, 2 with 'Hours' means every 2 hours.
        Use this to control the frequency of recurring jobs throughout the day, such as every 15 minutes for monitoring jobs or every 4 hours for maintenance tasks.
        Valid ranges are 1-59 for seconds/minutes and 1-23 for hours.

    .PARAMETER FrequencyRelativeInterval
        Specifies which occurrence of the day within the month for MonthlyRelative schedules. Controls whether you want the first, second, third, fourth, or last occurrence.
        Use this for schedules like "first Monday of every month" (First + Monday) or "last Friday of every month" (Last + Friday). Only applies when FrequencyType is 'MonthlyRelative'.
        Common values are 'First', 'Second', 'Third', 'Fourth', or 'Last'.

    .PARAMETER FrequencyRecurrenceFactor
        Controls how often the schedule repeats by specifying the interval between occurrences. For weekly schedules, this is the number of weeks between runs; for monthly schedules, it's the number of months.
        Use this to create schedules like "every 2 weeks on Monday" (FrequencyRecurrenceFactor=2) or "every 3 months on the 15th" (FrequencyRecurrenceFactor=3). Only applies to Weekly, Monthly, and MonthlyRelative frequency types.
        Must be at least 1, and is commonly used for less frequent maintenance tasks or reports.

    .PARAMETER StartDate
        Sets the earliest date when the schedule becomes active and the job can start running. Must be in yyyyMMdd format (e.g., '20240315').
        Use this to delay job execution until a future date or to replace an existing start date. The schedule will not run before this date even if other timing conditions are met.

    .PARAMETER EndDate
        Sets the last date when the schedule will be active and can execute the job. Must be in yyyyMMdd format and cannot be before StartDate.
        Use this to automatically disable schedules after a specific date, useful for temporary jobs or time-limited maintenance tasks. After this date, the schedule remains but will not execute.

    .PARAMETER StartTime
        Sets the daily start time when the job can begin executing, using 24-hour format HHMMSS (e.g., '080000' for 8:00 AM, '143000' for 2:30 PM).
        Use this to schedule jobs during specific maintenance windows or business hours. For jobs with subday frequency, this is when the recurring pattern starts each day.

    .PARAMETER EndTime
        Sets the daily end time when the job can no longer start executing, using 24-hour format HHMMSS (e.g., '180000' for 6:00 PM, '235959' for just before midnight).
        Use this to prevent jobs from starting during peak business hours or to ensure long-running jobs complete before critical operations begin. For recurring jobs, this stops new executions but doesn't kill running jobs.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Bypasses some parameter validation errors by applying sensible defaults and removes any existing schedules with the same name before creating new ones.
        Use this when you want to overwrite existing schedules or when working with edge cases where strict validation might prevent legitimate schedule modifications.
        Be cautious as this can remove existing schedules without prompting.

    .NOTES
        Tags: Agent, Job, JobStep
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentSchedule

    .EXAMPLE
        PS C:\> Set-DbaAgentSchedule -SqlInstance sql1 -Job Job1 -ScheduleName daily -Enabled

        Changes the schedule for Job1 with the name 'daily' to enabled

    .EXAMPLE
        PS C:\> Set-DbaAgentSchedule -SqlInstance sql1 -Job Job1 -ScheduleName daily -NewName weekly -FrequencyType Weekly -FrequencyInterval Monday, Wednesday, Friday

        Changes the schedule for Job1 with the name daily to have a new name weekly

    .EXAMPLE
        PS C:\> Set-DbaAgentSchedule -SqlInstance sql1 -Job Job1, Job2, Job3 -ScheduleName daily -StartTime '230000'

        Changes the start time of the schedule for Job1 to 11 PM for multiple jobs

    .EXAMPLE
        PS C:\> Set-DbaAgentSchedule -SqlInstance sql1, sql2, sql3 -Job Job1 -ScheduleName daily -Enabled

        Changes the schedule for Job1 with the name daily to enabled on multiple servers

    .EXAMPLE
        PS C:\> sql1, sql2, sql3 | Set-DbaAgentSchedule -Job Job1 -ScheduleName daily -Enabled

        Changes the schedule for Job1 with the name 'daily' to enabled on multiple servers using pipe line

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Job,
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$ScheduleName,
        [string]$NewName,
        [switch]$Enabled,
        [switch]$Disabled,
        [ValidateSet('Once', 'OneTime', 'Daily', 'Weekly', 'Monthly', 'MonthlyRelative', 'AgentStart', 'AutoStart', 'IdleComputer', 'OnIdle', 1, 4, 8, 16, 32, 64, 128)]
        [object]$FrequencyType,
        [object[]]$FrequencyInterval,
        [ValidateSet(1, 'Once', 'Time', 2, 'Seconds', 'Second', 4, 'Minutes', 'Minute', 8, 'Hours', 'Hour')]
        [object]$FrequencySubdayType,
        [int]$FrequencySubdayInterval,
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$FrequencyRelativeInterval,
        [int]$FrequencyRecurrenceFactor,
        [string]$StartDate,
        [string]$EndDate,
        [string]$StartTime,
        [string]$EndTime,
        [switch]$EnableException,
        [switch]$Force
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Check of the FrequencyType value is of type string and set the integer value
        if ($FrequencyType -notin 1, 4, 8, 16, 32, 64, 128) {
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
        }

        # Check of the FrequencySubdayType value is of type string and set the integer value
        if ($FrequencySubdayType -notin 0, 1, 2, 4, 8) {
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
                default { 0 }
            }
        }

        # Check if the interval for daily frequency is valid
        if (($FrequencyType -in 4) -and ($FrequencyInterval -lt 1 -or $FrequencyInterval -ge 365) -and (-not ($FrequencyInterval -eq "EveryDay")) -and (-not $Force)) {
            Stop-Function -Message "The daily frequency type requires a frequency interval to be between 1 and 365 or 'EveryDay'." -Target $SqlInstance
            return
        }

        # Check if the recurrence factor is set for weekly or monthly interval
        if ($FrequencyRecurrenceFactor -and ($FrequencyType -in 8, 16) -and $FrequencyRecurrenceFactor -lt 1) {
            if ($Force) {
                $FrequencyRecurrenceFactor = 1
                Write-Message -Message "Recurrence factor not set for weekly or monthly interval. Setting it to $FrequencyRecurrenceFactor." -Level Verbose
            } else {
                Stop-Function -Message "The recurrence factor $FrequencyRecurrenceFactor needs to be at least on when using a weekly or monthly interval." -Target $SqlInstance
                return
            }
        }

        # Check the subday interval
        if (($FrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($FrequencySubdayInterval -ge 1 -or $FrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 59 when subday type is 'Seconds' or 'Minutes'" -Target $SqlInstance
            return
        } elseif (($FrequencySubdayType -eq 8, "Hours") -and (-not ($FrequencySubdayInterval -ge 1 -and $FrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 23 when subday type is 'Hours'" -Target $SqlInstance
            return
        }

        # Check of the FrequencyInterval value is of type string and set the integer value
        if (($null -ne $FrequencyType)) {
            # Create the interval to hold the value(s)
            [int]$Interval = 0

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
                # Loop through the array
                foreach ($Item in $FrequencyInterval) {
                    switch ($Item) {
                        "Sunday" { $Interval += 1 }
                        "Monday" { $Interval += 2 }
                        "Tuesday" { $Interval += 4 }
                        "Wednesday" { $Interval += 8 }
                        "Thursday" { $Interval += 16 }
                        "Friday" { $Interval += 32 }
                        "Saturday" { $Interval += 64 }
                        "Weekdays" { $Interval = 62 }
                        "Weekend" { $Interval = 65 }
                        "EveryDay" { $Interval = 127 }
                        1 { $Interval += 1 }
                        2 { $Interval += 2 }
                        4 { $Interval += 4 }
                        8 { $Interval += 8 }
                        16 { $Interval += 16 }
                        32 { $Interval += 32 }
                        64 { $Interval += 64 }
                        62 { $Interval = 62 }
                        65 { $Interval = 65 }
                        127 { $Interval = 127 }
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
            if ($FrequencyType -in 32, 'MonthlyRelative') {
                # Loop through the array
                foreach ($Item in $FrequencyInterval) {
                    switch ($Item) {
                        "Sunday" { $Interval += 1 }
                        "Monday" { $Interval += 2 }
                        "Tuesday" { $Interval += 3 }
                        "Wednesday" { $Interval += 4 }
                        "Thursday" { $Interval += 5 }
                        "Friday" { $Interval += 6 }
                        "Saturday" { $Interval += 7 }
                        "Day" { $Interval += 8 }
                        "Weekday" { $Interval += 9 }
                        "WeekendDay" { $Interval += 10 }
                        1 { $Interval += 1 }
                        2 { $Interval += 2 }
                        3 { $Interval += 3 }
                        4 { $Interval += 4 }
                        5 { $Interval += 5 }
                        6 { $Interval += 6 }
                        7 { $Interval += 7 }
                        8 { $Interval += 8 }
                        9 { $Interval += 9 }
                        10 { $Interval += 10 }
                    }
                }
            }
        }

        # Check of the relative FrequencyInterval value is of type string and set the integer value
        if (($FrequencyRelativeInterval -notin 1, 2, 4, 8, 16) -and ($null -ne $FrequencyRelativeInterval)) {
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
        }

        # Setup the regex
        $RegexDate = '(?<!\d)(?:(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:(?:0[13578]|1[02])31)|(?:(?:0[1,3-9]|1[0-2])(?:29|30)))|(?:(?:(?:(?:1[6-9]|[2-9]\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00)))0229)|(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:0?[1-9])|(?:1[0-2]))(?:0?[1-9]|1\d|2[0-8]))(?!\d)'
        $RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'

        # Check the start date
        if ($StartDate -and ($StartDate -notmatch $RegexDate)) {
            Stop-Function -Message "Start date $StartDate needs to be a valid date with format yyyyMMdd" -Target $SqlInstance
            return
        }

        # Check the end date
        if ($EndDate -and ($EndDate -notmatch $RegexDate)) {
            Stop-Function -Message "End date $EndDate needs to be a valid date with format yyyyMMdd" -Target $SqlInstance
            return
        } elseif ($EndDate -and ($EndDate -lt $StartDate)) {
            Stop-Function -Message "End date $EndDate cannot be before start date $StartDate" -Target $SqlInstance
            return
        }

        # Check the start time
        if ($StartTime -and ($StartTime -notmatch $RegexTime)) {
            Stop-Function -Message "Start time $StartTime needs to match between '000000' and '235959'. Schedule $ScheduleName not set." -Target $SqlInstance
            return
        }

        # Check the end time
        if ($EndTime -and ($EndTime -notmatch $RegexTime)) {
            Stop-Function -Message "End time $EndTime needs to match between '000000' and '235959'. Schedule $ScheduleName not set." -Target $SqlInstance
            return
        }

        #Format dates and times
        if ($StartDate) {
            $StartDate = $StartDate.Insert(6, '-').Insert(4, '-')
        }
        if ($EndDate) {
            $EndDate = $EndDate.Insert(6, '-').Insert(4, '-')
        }
        if ($StartTime) {
            $StartTime = $StartTime.Insert(4, ':').Insert(2, ':')
        }
        if ($EndTime) {
            $EndTime = $EndTime.Insert(4, ':').Insert(2, ':')
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

            foreach ($j in $Job) {
                # Check if the job exists
                if ($server.JobServer.Jobs.Name -notcontains $j) {
                    Write-Message -Message "Job $j doesn't exists on $instance" -Level Warning
                } else {
                    # Check if the job schedule exists
                    if ($server.JobServer.Jobs[$j].JobSchedules.Name -notcontains $ScheduleName) {
                        Stop-Function -Message "Schedule $ScheduleName doesn't exists for job $j on $instance" -Target $instance -Continue
                    } else {
                        # Get the job schedule
                        # If for some reason the there are multiple schedules with the same name, the first on is chosen
                        $JobSchedule = $server.JobServer.Jobs[$j].JobSchedules[$ScheduleName][0]

                        # Set the frequency interval to make up for newly created schedules without an interval
                        if ($JobSchedule.FrequencyInterval -eq 0 -and $Interval -lt 1) {
                            $Interval = 1
                        }

                        #region job step options
                        # Setting the options for the job schedule
                        if ($NewName) {
                            if ($Pscmdlet.ShouldProcess($server, "Setting job schedule $ScheduleName Name to $NewName")) {
                                $JobSchedule.Rename($NewName)
                            }
                        }

                        if ($Enabled) {
                            Write-Message -Message "Setting job schedule to enabled for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.IsEnabled = $true
                        }

                        if ($Disabled) {
                            Write-Message -Message "Setting job schedule to disabled for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.IsEnabled = $false
                        }

                        if ($FrequencyType -ge 1) {
                            Write-Message -Message "Setting job schedule frequency to $FrequencyType for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.FrequencyTypes = $FrequencyType
                        }

                        if ($Interval -ge 1) {
                            Write-Message -Message "Setting job schedule frequency interval to $Interval for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.FrequencyInterval = $Interval
                        }

                        if ($FrequencySubdayType -ge 1) {
                            Write-Message -Message "Setting job schedule frequency subday type to $FrequencySubdayType for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.FrequencySubDayTypes = $FrequencySubdayType
                        }

                        if ($FrequencySubdayInterval -ge 1) {
                            Write-Message -Message "Setting job schedule frequency subday interval to $FrequencySubdayInterval for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.FrequencySubDayInterval = $FrequencySubdayInterval
                        }

                        if (($FrequencyRelativeInterval -ge 1) -and ($FrequencyType -eq 32)) {
                            Write-Message -Message "Setting job schedule frequency relative interval to $FrequencyRelativeInterval for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.FrequencyRelativeIntervals = $FrequencyRelativeInterval
                        }

                        if (($FrequencyRecurrenceFactor -ge 1) -and ($FrequencyType -in 8, 16, 32)) {
                            Write-Message -Message "Setting job schedule frequency recurrence factor to $FrequencyRecurrenceFactor for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.FrequencyRecurrenceFactor = $FrequencyRecurrenceFactor
                        }

                        if ($StartDate) {
                            Write-Message -Message "Setting job schedule start date to $StartDate for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.ActiveStartDate = $StartDate
                        }

                        if ($EndDate) {
                            Write-Message -Message "Setting job schedule end date to $EndDate for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.ActiveEndDate = $EndDate
                        }

                        if ($StartTime) {
                            Write-Message -Message "Setting job schedule start time to $StartTime for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.ActiveStartTimeOfDay = $StartTime
                        }

                        if ($EndTime) {
                            Write-Message -Message "Setting job schedule end time to $EndTime for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.ActiveEndTimeOfDay = $EndTime
                        }
                        #endregion job step options

                        # Execute the query
                        if ($PSCmdlet.ShouldProcess($instance, "Committing changes for schedule $ScheduleName for job $j on $instance")) {
                            try {
                                # Excute the query and save the result
                                Write-Message -Message "Committing changes for schedule $ScheduleName for job $j" -Level Verbose

                                $JobSchedule.Alter()

                                # Return updated schedule
                                Get-DbaAgentSchedule -SqlInstance $server -ScheduleUid $JobSchedule.ScheduleUid
                            } catch {
                                Stop-Function -Message "Something went wrong changing the schedule" -Target $instance -ErrorRecord $_ -Continue
                                return
                            }
                        }
                    }
                }
            } # foreach object job
        } # foreach object instance
    } # process

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished changing the job schedule(s)" -Level Verbose
    }
}