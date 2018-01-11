#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function New-DbaAgentSchedule {
    <#
        .SYNOPSIS
            New-DbaAgentSchedule creates a new schedule in the msdb database.

        .DESCRIPTION
            New-DbaAgentSchedule will help create a new schedule for a job.
            If the job parameter is not supplied the schedule will not be attached to a job.

        .PARAMETER SqlInstance
            SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

            To use: $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Job
            The name of the job that has the schedule.

        .PARAMETER Schedule
            The name of the schedule.

        .PARAMETER Disabled
            Set the schedule to disabled. Default is enabled

        .PARAMETER FrequencyType
            A value indicating when a job is to be executed.

            Allowed values: Once, Daily, Weekly, Monthly, MonthlyRelative, AgentStart or IdleComputer

            If force is used the default will be "Once".

        .PARAMETER FrequencyInterval
            The days that a job is executed

            Allowed values: Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Weekdays, Weekend or EveryDay.
            The other allowed values are the numbers 1 to 31 for each day of the month.

            If "Weekdays", "Weekend" or "EveryDay" is used it over writes any other value that has been passed before.

            If force is used the default will be 1.

        .PARAMETER FrequencySubdayType
            Specifies the units for the subday FrequencyInterval.

            Allowed values: Time, Seconds, Minutes, or Hours

        .PARAMETER FrequencySubdayInterval
            The number of subday type periods to occur between each execution of a job.

        .PARAMETER FrequencyRelativeInterval
            A job's occurrence of FrequencyInterval in each month, if FrequencyInterval is 32 (monthlyrelative).

            Allowed values: First, Second, Third, Fourth or Last

        .PARAMETER FrequencyRecurrenceFactor
            The number of weeks or months between the scheduled execution of a job.

            FrequencyRecurrenceFactor is used only if FrequencyType is "Weekly", "Monthly" or "MonthlyRelative".

        .PARAMETER StartDate
            The date on which execution of a job can begin.

            If force is used the start date will be the current day

        .PARAMETER EndDate
            The date on which execution of a job can stop.

            If force is used the end date will be '9999-12-31'

        .PARAMETER StartTime
            The time on any day to begin execution of a job. Format HHMMSS / 24 hour clock.
            Example: '010000' for 01:00:00 AM.
            Example: '140000' for 02:00:00 PM.

            If force is used the start time will be '00:00:00'

        .PARAMETER EndTime
            The time on any day to end execution of a job. Format HHMMSS / 24 hour clock.
            Example: '010000' for 01:00:00 AM.
            Example: '140000' for 02:00:00 PM.

            If force is used the start time will be '23:59:59'

        .PARAMETER Owner
            The name of the server principal that owns the schedule. If no value is given the schedule is owned by the creator.

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
            Tags: Agent, Job, Job Step
            Author: Sander Stad (@sqlstad, sqlstad.nl)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/New-DbaAgentSchedule

        .EXAMPLE
            New-DbaAgentSchedule -SqlInstance localhost\SQL2016 -Schedule daily -FrequencyType Daily -FrequencyInterval Everyday -Force

            Creates a schedule with a daily frequency every day. It assumes default values for the start date, start time, end date and end time due to -Force.

        .EXAMPLE
            New-DbaAgentSchedule -SqlInstance sstad-pc -Schedule MonthlyTest -FrequencyType Monthly -FrequencyInterval 10 -FrequencyRecurrenceFactor 1 -Force

            Create a schedule with a monhtly frequency occuring every 10th of the month. It assumes default values for the start date, start time, end date and end time due to -Force.

    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]
        $SqlCredential,
        [object[]]$Job,
        [object]$Schedule,
        [switch]$Disabled,
        [ValidateSet('Once', 'Daily', 'Weekly', 'Monthly', 'MonthlyRelative', 'AgentStart', 'IdleComputer')]
        [object]$FrequencyType,
        [ValidateSet('EveryDay', 'Weekdays', 'Weekend', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31)]
        [object[]]$FrequencyInterval,
        [ValidateSet('Time', 'Seconds', 'Minutes', 'Hours')]
        [object]$FrequencySubdayType,
        [int]$FrequencySubdayInterval,
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$FrequencyRelativeInterval,
        [int]$FrequencyRecurrenceFactor,
        [string]$StartDate,
        [string]$EndDate,
        [string]$StartTime,
        [string]$EndTime,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        # if a Schedule is not provided there is no much point
        if (!$Schedule) {
            Stop-Function -Message "A schedule was not provided! Please provide a schedule name."
            return
        }

        [int]$Interval = 0

        # Translate FrequencyType value from string to the integer value
        if (!$FrequencyType -or $FrequencyType) {
            [int]$FrequencyType =
            switch ($FrequencyType) {
                "Once" { 1 }
                "Daily" { 4 }
                "Weekly" { 8 }
                "Monthly" { 16 }
                "MonthlyRelative" { 32 }
                "AgentStart" { 64 }
                "IdleComputer" { 128 }
                default { 1 }
            }
        }

        # Translate FrequencySubdayType value from string to the integer value
        if (!$FrequencySubdayType -or $FrequencySubdayType) {
            [int]$FrequencySubdayType =
            switch ($FrequencySubdayType) {
                "Time" { 1 }
                "Seconds" { 2 }
                "Minutes" { 4 }
                "Hours" { 8 }
                default { 1 }
            }
        }

        # Check of the relative FrequencyInterval value is of type string and set the integer value
        [int]$FrequencyRelativeInterval =
        switch ($FrequencyRelativeInterval) {
            "First" { 1 }
            "Second" { 2 }
            "Third" { 4 }
            "Fourth" { 8 }
            "Last" { 16 }
            "Unused" { 0 }
            default {0}
        }

        # Check if the interval is valid
        if (($FrequencyType -in 4, "Daily") -and (($FrequencyInterval -lt 1 -or $FrequencyInterval -ge 365) -and -not $FrequencyInterval -eq "EveryDay")) {
            Stop-Function -Message "The frequency interval $FrequencyInterval requires a frequency interval to be between 1 and 365." -Target $SqlInstance
            return
        }

        # Check if the recurrence factor is set for weekly or monthly interval
        if (($FrequencyType -in (16, 8)) -and $FrequencyRecurrenceFactor -lt 1) {
            if ($Force) {
                $FrequencyRecurrenceFactor = 1
                Write-Message -Message "Recurrence factor not set for weekly or monthly interval. Setting it to $FrequencyRecurrenceFactor." -Level Verbose
            }
            else {
                Stop-Function -Message "The recurrence factor $FrequencyRecurrenceFactor (parameter FrequencyRecurrenceFactor) needs to be at least one when using a weekly or monthly interval." -Target $SqlInstance
                return
            }
        }

        # Check the subday interval
        if (($FrequencySubdayType -in 2, "Seconds", 4, "Minutes") -and (-not ($FrequencySubdayInterval -ge 1 -or $FrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 59 when subday type is 'Seconds' or 'Minutes'" -Target $SqlInstance
            return
        }
        elseif (($FrequencySubdayType -eq 8, "Hours") -and (-not ($FrequencySubdayInterval -ge 1 -and $FrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 23 when subday type is 'Hours'" -Target $SqlInstance
            return
        }

        # If the FrequencyInterval is set for the daily FrequencyType
        if ($FrequencyType -in 4, 'Daily') {
            # Create the interval to hold the value(s)
            [int]$Interval = 0

            # Create the interval to hold the value(s)
            switch ($FrequencyInterval) {
                "EveryDay" { $Interval = 1}
                default {$Interval = 1 }
            }

        }

        # If the FrequencyInterval is set for the weekly FrequencyType
        if ($FrequencyType -in 8, 'Weekly') {
            # Create the interval to hold the value(s)
            [int]$Interval = 0

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
                    "EveryDay" {$Interval = 127 }
                    1 { $Interval += 1 }
                    2 { $Interval += 2 }
                    4 { $Interval += 4 }
                    8 { $Interval += 8 }
                    16 { $Interval += 16 }
                    32 { $Interval += 32 }
                    64 { $Interval += 64 }
                    62 { $Interval = 62 }
                    65 { $Interval = 65 }
                    127 {$Interval = 127 }
                    default { $Interval = 0 }
                }
            }
        }

        # If the FrequencyInterval is set for the monthly FrequencyInterval
        if ($FrequencyType -in 16, 'Monthly') {
            # Create the interval to hold the value(s)
            [int]$Interval = 0

            # Loop through the array
            foreach ($Item in $FrequencyInterval) {
                $FrequencyInterval
                switch ($Item) {
                    {[int]$_ -ge 1 -and [int]$_ -le 31} { $Interval = [int]$Item }
                }
            }


        }

        # If the FrequencyInterval is set for the relative monthly FrequencyInterval
        if ($FrequencyType -eq 32) {
            # Create the interval to hold the value(s)
            [int]$Interval = 0

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

        # Check if the interval is valid for the frequency
        if ($FrequencyType -eq 0) {
            if ($Force) {
                Write-Message -Message "Parameter FrequencyType must be set to at least [Once]. Setting it to 'Once'." -Level Warning
                $FrequencyType = 1
            }
            else {
                Stop-Function -Message "Parameter FrequencyType must be set to at least [Once]" -Target $SqlInstance
                return
            }
        }

        # Check if the interval is valid for the frequency
        if (($FrequencyType -in 4, 8, 32) -and ($Interval -lt 1)) {
            if ($Force) {
                Write-Message -Message "Parameter FrequencyInterval must be provided for a recurring schedule. Setting it to first day of the week." -Level Warning
                $Interval = 1
            }
            else {
                Stop-Function -Message "Parameter FrequencyInterval must be provided for a recurring schedule." -Target $SqlInstance
                return
            }
        }

        # Setup the regex
        $RegexDate = '(?<!\d)(?:(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:(?:0[13578]|1[02])31)|(?:(?:0[1,3-9]|1[0-2])(?:29|30)))|(?:(?:(?:(?:1[6-9]|[2-9]\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00)))0229)|(?:(?:1[6-9]|[2-9]\d)?\d{2})(?:(?:0?[1-9])|(?:1[0-2]))(?:0?[1-9]|1\d|2[0-8]))(?!\d)'
        $RegexTime = '^(?:(?:([01]?\d|2[0-3]))?([0-5]?\d))?([0-5]?\d)$'

        # Check the start date
        if (-not $StartDate -and $Force) {
            $StartDate = Get-Date -Format 'yyyyMMdd'
            Write-Message -Message "Start date was not set. Force is being used. Setting it to $StartDate" -Level Verbose
        }
        elseif (-not $StartDate) {
            Stop-Function -Message "Please enter a start date or use -Force to use defaults." -Target $SqlInstance
            return
        }
        elseif ($StartDate -notmatch $RegexDate) {
            Stop-Function -Message "Start date $StartDate needs to be a valid date with format yyyyMMdd" -Target $SqlInstance
            return
        }

        # Check the end date
        if (-not $EndDate -and $Force) {
            $EndDate = '99991231'
            Write-Message -Message "End date was not set. Force is being used. Setting it to $EndDate" -Level Verbose
        }
        elseif (-not $EndDate) {
            Stop-Function -Message "Please enter an end date or use -Force to use defaults." -Target $SqlInstance
            return
        }

        elseif ($EndDate -notmatch $RegexDate) {
            Stop-Function -Message "End date $EndDate needs to be a valid date with format yyyyMMdd" -Target $SqlInstance
            return
        }
        elseif ($EndDate -lt $StartDate) {
            Stop-Function -Message "End date $EndDate cannot be before start date $StartDate" -Target $SqlInstance
            return
        }

        # Check the start time
        if (-not $StartTime -and $Force) {
            $StartTime = '000000'
            Write-Message -Message "Start time was not set. Force is being used. Setting it to $StartTime" -Level Verbose
        }
        elseif (-not $StartTime) {
            Stop-Function -Message "Please enter a start time or use -Force to use defaults." -Target $SqlInstance
            return
        }
        elseif ($StartTime -notmatch $RegexTime) {
            Stop-Function -Message "Start time $StartTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }

        # Check the end time
        if (-not $EndTime -and $Force) {
            $EndTime = '235959'
            Write-Message -Message "End time was not set. Force is being used. Setting it to $EndTime" -Level Verbose
        }
        elseif (-not $EndTime) {
            Stop-Function -Message "Please enter an end time or use -Force to use defaults." -Target $SqlInstance
            return
        }
        elseif ($EndTime -notmatch $RegexTime) {
            Stop-Function -Message "End time $EndTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Check if the jobs parameter is set
            if ($Job) {
                # Loop through each of the jobs
                foreach ($j in $Job) {

                    # Check if the job exists
                    if ($Server.JobServer.Jobs.Name -notcontains $j) {
                        Write-Message -Message "Job $j doesn't exists on $instance" -Level Warning
                    }
                    else {
                        # Create the job schedule object
                        try {
                            # Get the job
                            $smoJob = $Server.JobServer.Jobs[$j]

                            # Check if schedule already exists with the same name
                            if ($Server.JobServer.JobSchedules.Name -contains $Schedule) {
                                # Check if force is set which will remove the other schedule
                                if ($Force) {
                                    if ($PSCmdlet.ShouldProcess($instance, "Removing the schedule $Schedule on $instance")) {
                                        # Removing schedule
                                        Remove-DbaAgentSchedule -SqlInstance $instance -SqlCredential $SqlCredential -Schedule $Schedule -Force:$Force
                                    }
                                }
                                else {
                                    Stop-Function -Message "Schedule $Schedule already exists for job $j on instance $instance" -Target $instance -ErrorRecord $_ -Continue
                                }
                            }

                            # Create the job schedule
                            $JobSchedule = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobSchedule($smoJob, $Schedule)

                        }
                        catch {
                            Stop-Function -Message "Something went wrong creating the job schedule $Schedule for job $j." -Target $instance -ErrorRecord $_ -Continue
                        }

                        #region job schedule options
                        if ($Disabled) {
                            Write-Message -Message "Setting job schedule to disabled" -Level Verbose
                            $JobSchedule.IsEnabled = $false
                        }
                        else {
                            Write-Message -Message "Setting job schedule to enabled" -Level Verbose
                            $JobSchedule.IsEnabled = $true
                        }

                        if ($Interval -ge 0) {
                            Write-Message -Message "Setting job schedule frequency interval to $Interval" -Level Verbose
                            $JobSchedule.FrequencyInterval = $Interval
                        }

                        if ($FrequencyType -ge 1) {
                            Write-Message -Message "Setting job schedule frequency to $FrequencyType" -Level Verbose
                            $JobSchedule.FrequencyTypes = $FrequencyType
                        }

                        if ($FrequencySubdayType -ge 1) {
                            Write-Message -Message "Setting job schedule frequency subday type to $FrequencySubdayType" -Level Verbose
                            $JobSchedule.FrequencySubDayTypes = $FrequencySubdayType
                        }

                        if ($FrequencySubdayInterval -ge 1) {
                            Write-Message -Message "Setting job schedule frequency subday interval to $FrequencySubdayInterval" -Level Verbose
                            $JobSchedule.FrequencySubDayInterval = $FrequencySubdayInterval
                        }

                        if (($FrequencyRelativeInterval -ge 1) -and ($FrequencyType -eq 32)) {
                            Write-Message -Message "Setting job schedule frequency relative interval to $FrequencyRelativeInterval" -Level Verbose
                            $JobSchedule.FrequencyRelativeIntervals = $FrequencyRelativeInterval
                        }

                        if (($FrequencyRecurrenceFactor -ge 1) -and ($FrequencyType -in 8, 16, 32)) {
                            Write-Message -Message "Setting job schedule frequency recurrence factor to $FrequencyRecurrenceFactor" -Level Verbose
                            $JobSchedule.FrequencyRecurrenceFactor = $FrequencyRecurrenceFactor
                        }

                        if ($StartDate) {
                            $StartDate = $StartDate.Insert(6, '-').Insert(4, '-')
                            Write-Message -Message "Setting job schedule start date to $StartDate" -Level Verbose
                            $JobSchedule.ActiveStartDate = $StartDate
                        }

                        if ($EndDate) {
                            $EndDate = $EndDate.Insert(6, '-').Insert(4, '-')
                            Write-Message -Message "Setting job schedule end date to $EndDate" -Level Verbose
                            $JobSchedule.ActiveEndDate = $EndDate
                        }

                        if ($StartTime) {
                            $StartTime = $StartTime.Insert(4, ':').Insert(2, ':')
                            Write-Message -Message "Setting job schedule start time to $StartTime" -Level Verbose
                            $JobSchedule.ActiveStartTimeOfDay = $StartTime
                        }

                        if ($EndTime) {
                            $EndTime = $EndTime.Insert(4, ':').Insert(2, ':')
                            Write-Message -Message "Setting job schedule end time to $EndTime" -Level Verbose
                            $JobSchedule.ActiveEndTimeOfDay = $EndTime
                        }
                        #endregion job schedule options

                        # Create the schedule
                        if ($PSCmdlet.ShouldProcess($SqlInstance, "Adding the schedule $Schedule to job $j on $instance")) {
                            try {
                                Write-Message -Message "Adding the schedule $Schedule to job $j" -Level Verbose
                                #$JobSchedule
                                $JobSchedule.Create()

                                Write-Message -Message "Job schedule created with UID $($JobSchedule.ScheduleUid)" -Level Verbose
                            }
                            catch {
                                Stop-Function -Message "Something went wrong adding the schedule" -Target $instance -ErrorRecord $_ -Continue

                            }

                            # Output the job schedule
                            return $JobSchedule
                        }
                    }
                } # foreach object job
            } # end if job
            else {
                # Create the schedule
                $JobSchedule = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobSchedule($Server.JobServer, $Schedule)

                #region job schedule options
                if ($Disabled) {
                    Write-Message -Message "Setting job schedule to disabled" -Level Verbose
                    $JobSchedule.IsEnabled = $false
                }
                else {
                    Write-Message -Message "Setting job schedule to enabled" -Level Verbose
                    $JobSchedule.IsEnabled = $true
                }

                if ($Interval -ge 1) {
                    Write-Message -Message "Setting job schedule frequency interval to $Interval" -Level Verbose
                    $JobSchedule.FrequencyInterval = $Interval
                }

                if ($FrequencyType -ge 1) {
                    Write-Message -Message "Setting job schedule frequency to $FrequencyType" -Level Verbose
                    $JobSchedule.FrequencyTypes = $FrequencyType
                }

                if ($FrequencySubdayType -ge 1) {
                    Write-Message -Message "Setting job schedule frequency subday type to $FrequencySubdayType" -Level Verbose
                    $JobSchedule.FrequencySubDayTypes = $FrequencySubdayType
                }

                if ($FrequencySubdayInterval -ge 1) {
                    Write-Message -Message "Setting job schedule frequency subday interval to $FrequencySubdayInterval" -Level Verbose
                    $JobSchedule.FrequencySubDayInterval = $FrequencySubdayInterval
                }

                if (($FrequencyRelativeInterval -ge 1) -and ($FrequencyType -eq 32)) {
                    Write-Message -Message "Setting job schedule frequency relative interval to $FrequencyRelativeInterval" -Level Verbose
                    $JobSchedule.FrequencyRelativeIntervals = $FrequencyRelativeInterval
                }

                if (($FrequencyRecurrenceFactor -ge 1) -and ($FrequencyType -in 8, 16, 32)) {
                    Write-Message -Message "Setting job schedule frequency recurrence factor to $FrequencyRecurrenceFactor" -Level Verbose
                    $JobSchedule.FrequencyRecurrenceFactor = $FrequencyRecurrenceFactor
                }

                if ($StartDate) {
                    $StartDate = $StartDate.Insert(6, '-').Insert(4, '-')
                    Write-Message -Message "Setting job schedule start date to $StartDate" -Level Verbose
                    $JobSchedule.ActiveStartDate = $StartDate
                }

                if ($EndDate) {
                    $EndDate = $EndDate.Insert(6, '-').Insert(4, '-')
                    Write-Message -Message "Setting job schedule end date to $EndDate" -Level Verbose
                    $JobSchedule.ActiveEndDate = $EndDate
                }

                if ($StartTime) {
                    $StartTime = $StartTime.Insert(4, ':').Insert(2, ':')
                    Write-Message -Message "Setting job schedule start time to $StartTime" -Level Verbose
                    $JobSchedule.ActiveStartTimeOfDay = $StartTime
                }

                if ($EndTime) {
                    $EndTime = $EndTime.Insert(4, ':').Insert(2, ':')
                    Write-Message -Message "Setting job schedule end time to $EndTime" -Level Verbose
                    $JobSchedule.ActiveEndTimeOfDay = $EndTime
                }

                # Create the schedule
                if ($PSCmdlet.ShouldProcess($SqlInstance, "Adding the schedule $schedule on $instance")) {
                    try {
                        Write-Message -Message "Adding the schedule $JobSchedule on instance $instance" -Level Verbose

                        $JobSchedule.Create()

                        Write-Message -Message "Job schedule created with UID $($JobSchedule.ScheduleUid)" -Level Verbose
                    }
                    catch {
                        Stop-Function -Message "Something went wrong adding the schedule." -Target $instance -ErrorRecord $_ -Continue
                    }

                    # Output the job schedule
                    return $JobSchedule
                }
            }
        } # foreach object instance
    } #process

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished creating job schedule(s)." -Level Verbose
    }
}