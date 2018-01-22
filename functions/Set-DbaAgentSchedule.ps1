#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Set-DbaAgentSchedule {
    <#
.SYNOPSIS
Set-DbaAgentSchedule updates a schedule in the msdb database.

.DESCRIPTION
Set-DbaAgentSchedule will help update a schedule for a job. It does not attach the schedule to a job.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Job
The name of the job that has the schedule.

.PARAMETER ScheduleName
The name of the schedule.

.PARAMETER NewName
The new name for the schedule.

.PARAMETER Enabled
Set the schedule to enabled.

.PARAMETER Disabled
Set the schedule to disabled.

.PARAMETER FrequencyType
A value indicating when a job is to be executed.
Allowed values are 1, "Once", 4, "Daily", 8, "Weekly", 16, "Monthly", 32, "MonthlyRelative", 64, "AgentStart", 128 or "IdleComputer"

.PARAMETER FrequencyInterval
The days that a job is executed
Allowed values are 1, "Sunday", 2, "Monday", 4, "Tuesday", 8, "Wednesday", 16, "Thursday", 32, "Friday", 64, "Saturday", 62, "Weekdays", 65, "Weekend", 127, "EveryDay".
If 62, "Weekdays", 65, "Weekend", 127, "EveryDay" is used it overwwrites any other value that has been passed before.

.PARAMETER FrequencySubdayType
Specifies the units for the subday FrequencyInterval.
Allowed values are 1, "Time", 2, "Seconds", 4, "Minutes", 8 or "Hours"

.PARAMETER FrequencySubdayInterval
The number of subday type periods to occur between each execution of a job.

.PARAMETER FrequencySubdayInterval
The number of subday type periods to occur between each execution of a job.

.PARAMETER FrequencyRelativeInterval
A job's occurrence of FrequencyInterval in each month, if FrequencyInterval is 32 (monthlyrelative).

.PARAMETER FrequencyRecurrenceFactor
The number of weeks or months between the scheduled execution of a job. FrequencyRecurrenceFactor is used only if FrequencyType is 8, "Weekly", 16, "Monthly", 32 or "MonthlyRelative".

.PARAMETER StartDate
The date on which execution of a job can begin.

.PARAMETER EndDate
The date on which execution of a job can stop.

.PARAMETER StartTime
The time on any day to begin execution of a job. Format HHMMSS / 24 hour clock.
Example: '010000' for 01:00:00 AM.
Example: '140000' for 02:00:00 PM.

.PARAMETER EndTime
The time on any day to end execution of a job. Format HHMMSS / 24 hour clock.
Example: '010000' for 01:00:00 AM.
Example: '140000' for 02:00:00 PM.

.PARAMETER Owner
The name of the server principal that owns the schedule. If no value is given the schedule is owned by the creator.

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.PARAMETER Force
The force parameter will ignore some errors in the parameters and assume defaults.
It will also remove the any present schedules with the same name for the specific job.

.NOTES
Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Agent, Job, Job Step

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Set-DbaAgentSchedule

.EXAMPLE
Set-DbaAgentSchedule -SqlInstance sql1 -Job Job1 -ScheduleName daily -Enabled
Changes the schedule for Job1 with the name 'daily' to enabled

.EXAMPLE
Set-DbaAgentSchedule -SqlInstance sql1 -Job Job1 -ScheduleName daily -NewName weekly -FrequencyType Weekly -FrequencyInterval Monday, Wednesday, Friday
Changes the schedule for Job1 with the name daily to have a new name weekly

.EXAMPLE
Set-DbaAgentSchedule -SqlInstance sql1 -Job Job1, Job2, Job3 -ScheduleName daily -StartTime '230000'
Changes the start time of the schedule for Job1 to 11 PM for multiple jobs

.EXAMPLE
Set-DbaAgentSchedule -SqlInstance sql1, sql2, sql3 -Job Job1 -ScheduleName daily -Enabled
Changes the schedule for Job1 with the name daily to enabled on multiple servers

.EXAMPLE
sql1, sql2, sql3 | Set-DbaAgentSchedule -Job Job1 -ScheduleName 'daily' -Enabled
Changes the schedule for Job1 with the name 'daily' to enabled on multiple servers using pipe line

#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]

    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(Mandatory = $false)]
        [PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Job,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScheduleName,
        [Parameter(Mandatory = $false)]
        [string]$NewName,
        [Parameter(Mandatory = $false)]
        [switch]$Enabled,
        [Parameter(Mandatory = $false)]
        [switch]$Disabled,
        [ValidateSet(1, "Once", 4, "Daily", 8, "Weekly", 16, "Monthly", 32, "MonthlyRelative", 64, "AgentStart", 128, "IdleComputer")]
        [object]$FrequencyType,
        [Parameter(Mandatory = $false)]
        [object[]]$FrequencyInterval,
        [Parameter(Mandatory = $false)]
        [ValidateSet(1, "Time", 2, "Seconds", 4, "Minutes", 8, "Hours")]
        [object]$FrequencySubdayType,
        [Parameter(Mandatory = $false)]
        [int]$FrequencySubdayInterval,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')]
        [object]$FrequencyRelativeInterval,
        [Parameter(Mandatory = $false)]
        [int]$FrequencyRecurrenceFactor,
        [Parameter(Mandatory = $false)]
        [string]$StartDate,
        [Parameter(Mandatory = $false)]
        [string]$EndDate,
        [Parameter(Mandatory = $false)]
        [string]$StartTime,
        [Parameter(Mandatory = $false)]
        [string]$EndTime,
        [Parameter(Mandatory = $false)]
        [switch][Alias('Silent')]$EnableException,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    begin {

        # Check of the FrequencyType value is of type string and set the integer value
        if ($FrequencyType -notin 0, 1, 4, 8, 16, 32, 64, 128) {
            [int]$FrequencyType = switch ($FrequencyType) { "Once" { 1 } "Daily" { 4 } "Weekly" { 8 } "Monthly" { 16 } "MonthlyRelative" { 32 } "AgentStart" { 64 } "IdleComputer" { 128 } }
        }

        # Check of the FrequencySubdayType value is of type string and set the integer value
        if ($FrequencySubdayType -notin 0, 1, 2, 4, 8) {
            [int]$FrequencySubdayType = switch ($FrequencySubdayType) { "Time" { 1 } "Seconds" { 2 } "Minutes" { 4 } "Hours" { 8 } default {0} }
        }

        # Check if the interval is valid
        if (($FrequencyType -eq 4) -and ($FrequencyInterval -lt 1 -or $FrequencyInterval -ge 365)) {
            Stop-Function -Message "The interval $FrequencyInterval needs to be higher than 1 and lower than 365 when using a daily frequency the interval." -Target $SqlInstance
            return
        }

        # Check if the recurrence factor is set for weekly or monthly interval
        if (($FrequencyType -in 8, 16) -and $FrequencyRecurrenceFactor -lt 1) {
            if ($Force) {
                $FrequencyRecurrenceFactor = 1
                Write-Message -Message "Recurrence factor not set for weekly or monthly interval. Setting it to $FrequencyRecurrenceFactor." -Level Verbose
            }
            else {
                Stop-Function -Message "The recurrence factor $FrequencyRecurrenceFactor needs to be at least on when using a weekly or monthly interval." -Target $SqlInstance
                return
            }
        }

        # Check the subday interval
        if (($FrequencySubdayType -in 2, 4) -and (-not ($FrequencySubdayInterval -ge 1 -or $FrequencySubdayInterval -le 59))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 59 when subday type is 2, 'Seconds', 4 or 'Minutes'" -Target $SqlInstance
            return
        }
        elseif (($FrequencySubdayType -eq 8) -and (-not ($FrequencySubdayInterval -ge 1 -and $FrequencySubdayInterval -le 23))) {
            Stop-Function -Message "Subday interval $FrequencySubdayInterval must be between 1 and 23 when subday type is 8 or 'Hours" -Target $SqlInstance
            return
        }

        # Check of the FrequencyInterval value is of type string and set the integer value
        if (($null -ne $FrequencyType)) {
            # Create the interval to hold the value(s)
            [int]$Interval = 0

            # If the FrequencyInterval is set for the weekly FrequencyType
            if ($FrequencyType -eq 8) {
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
                        31 { $Interval += 32 }
                        64 { $Interval += 64 }
                        62 { $Interval = 62 }
                        65 { $Interval = 65 }
                        127 {$Interval = 127 }
                    }
                }
            }

            # If the FrequencyInterval is set for the relative monthly FrequencyInterval
            if ($FrequencyType -eq 32) {
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
        if (($FrequencyRelativeInterval -notin 1, 2, 4, 8, 16) -and $null -ne $FrequencyRelativeInterval) {
            [int]$FrequencyRelativeInterval = switch ($FrequencyRelativeInterval) { "First" { 1 } "Second" { 2 } "Third" { 4 } "Fourth" { 8 } "Last" { 16 } "Unused" { 0 } default { 0 }}
        }

        # Check if the interval is valid
        if (($FrequencyType -eq 4) -and ($FrequencyInterval -lt 1 -or $FrequencyInterval -ge 365)) {
            Stop-Function -Message "The interval $FrequencyInterval needs to be higher than 1 and lower than 365 when using a daily frequency the interval." -Target $SqlInstance
            return
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
        }
        elseif ($EndDate -lt $StartDate) {
            Stop-Function -Message "End date $EndDate cannot be before start date $StartDate" -Target $SqlInstance
            return
        }

        # Check the start time
        if ($StartTime -and ($StartTime -notmatch $RegexTime)) {
            Stop-Function -Message "Start time $StartTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }

        # Check the end time
        if ($EndTime -and ($EndTime -notmatch $RegexTime)) {
            Stop-Function -Message "End time $EndTime needs to match between '000000' and '235959'" -Target $SqlInstance
            return
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $sqlinstance) {

            foreach ($j in $Job) {

                # Try connecting to the instance
                Write-Message -Message "Attempting to connect to $instance" -Level Verbose
                try {
                    $Server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                # Check if the job exists
                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    Write-Message -Message "Job $j doesn't exists on $instance" -Level Warning
                }
                else {
                    # Check if the job schedule exists
                    if ($Server.JobServer.Jobs[$j].JobSchedules.Name -notcontains $ScheduleName) {
                        Stop-Function -Message "Schedule $ScheduleName doesn't exists for job $j on $instance" -Target $instance -Continue
                    }
                    else {
                        # Get the job schedule
                        # If for some reason the there are multiple schedules with the same name, the first on is chosen
                        $JobSchedule = $Server.JobServer.Jobs[$j].JobSchedules[$ScheduleName][0]

                        #region job step options
                        # Setting the options for the job schedule
                        if ($NewName) {
                            Write-Message -Message "Setting job schedule name to $NewName for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.Rename($NewName)
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
                            $StartDate = $StartDate.Insert(6, '-').Insert(4, '-')
                            Write-Message -Message "Setting job schedule start date to $StartDate for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.StartDate = $StartDate
                        }

                        if ($EndDate) {
                            $EndDate = $EndDate.Insert(6, '-').Insert(4, '-')
                            Write-Message -Message "Setting job schedule end date to $EndDate for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.EndDate = $EndDate
                        }

                        if ($StartTime) {
                            $StartTime = $StartTime.Insert(4, ':').Insert(2, ':')
                            Write-Message -Message "Setting job schedule start time to $StartTime for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.ActiveStartTimeOfDay = $StartTime
                        }

                        if ($EndTime) {
                            $EndTime = $EndTime.Insert(4, ':').Insert(2, ':')
                            Write-Message -Message "Setting job schedule end time to $EndTime for schedule $ScheduleName" -Level Verbose
                            $JobSchedule.ActiveStartTimeOfDay = $EndTime
                        }
                        #endregion job step options

                        # Execute the query
                        if ($PSCmdlet.ShouldProcess($instance, "Changing the schedule $ScheduleName for job $j on $instance")) {
                            try {
                                # Excute the query and save the result
                                Write-Message -Message "Changing the schedule $ScheduleName for job $j" -Level Verbose

                                $JobSchedule.Alter()

                            }
                            catch {
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