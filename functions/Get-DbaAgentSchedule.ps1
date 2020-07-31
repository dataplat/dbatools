function Get-DbaAgentSchedule {
    <#
    .SYNOPSIS
        Returns all SQL Agent Shared Schedules on a SQL Server Agent.

    .DESCRIPTION
        This function returns SQL Agent Shared Schedules.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Schedule
        Parameter to filter the schedules returned

    .PARAMETER ScheduleUid
        The unique identifier of the schedule

    .PARAMETER Id
        Parameter to filter the schedules returned

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Schedule
        Author: Chris McKeown (@devopsfu), http://www.devopsfu.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentSchedule

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost

        Returns all SQL Agent Shared Schedules on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost, sql2016

        Returns all SQL Agent Shared Schedules for the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost, sql2016 -Id 3

        Returns the SQL Agent Shared Schedules with the Id of 3

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance localhost, sql2016 -ScheduleUid 'bf57fa7e-7720-4936-85a0-87d279db7eb7'

        Returns the SQL Agent Shared Schedules with the UID

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance sql2016 -Schedule "Maintenance10min","Maintenance60min"

        Returns the "Maintenance10min" & "Maintenance60min" schedules from the sql2016 SQL Server instance
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Schedule,
        [string[]]$ScheduleUid,
        [int[]]$Id,
        [switch]$EnableException
    )

    begin {
        function Get-ScheduleDescription {
            param (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [object]$currentschedule

            )

            # Get the culture to make sure the right date and time format is displayed
            $datetimeFormat = (Get-Culture).DateTimeFormat

            # Set the intial description
            $description = ""

            # Get the date and time values
            $startDate = Get-Date $currentschedule.ActiveStartDate -format $datetimeFormat.ShortDatePattern
            $startTime = Get-Date ($currentschedule.ActiveStartTimeOfDay.ToString()) -format $datetimeFormat.LongTimePattern
            $endDate = Get-Date $currentschedule.ActiveEndDate -format $datetimeFormat.ShortDatePattern
            $endTime = Get-Date ($currentschedule.ActiveEndTimeOfDay.ToString()) -format $datetimeFormat.LongTimePattern

            # Start setting the description based on the frequency type
            switch ($currentschedule.FrequencyTypes) {
                { ($_ -eq 1) -or ($_ -eq "Once") } { $description += "Occurs on $startDate at $startTime" }
                { ($_ -in 4, 8, 16, 32) -or ($_ -in "Daily", "Weekly", "Monthly") } { $description += "Occurs every " }
                { ($_ -eq 64) -or ($_ -eq "AutoStart") } { $description += "Start automatically when SQL Server Agent starts " }
                { ($_ -eq 128) -or ($_ -eq "OnIdle") } { $description += "Start whenever the CPUs become idle" }
            }

            # Check the frequency types for daily or weekly i.e.
            switch ($currentschedule.FrequencyTypes) {
                # Daily
                { $_ -in 4, "Daily" } {
                    if ($currentschedule.FrequencyInterval -eq 1) {
                        $description += "day "
                    } elseif ($currentschedule.FrequencyInterval -gt 1) {
                        $description += "$($currentschedule.FrequencyInterval) day(s) "
                    }
                }

                # Weekly
                { $_ -in 8, "Weekly" } {
                    # Check if it's for one or more weeks
                    if ($currentschedule.FrequencyRecurrenceFactor -eq 1) {
                        $description += "week on "
                    } elseif ($currentschedule.FrequencyRecurrenceFactor -gt 1) {
                        $description += "$($currentschedule.FrequencyRecurrenceFactor) week(s) on "
                    }

                    # Save the interval for the loop
                    $frequencyInterval = $currentschedule.FrequencyInterval

                    # Create the array to hold the days
                    $days = ($false, $false, $false, $false, $false, $false, $false)

                    # Loop through the days
                    while ($frequencyInterval -gt 0) {

                        switch ($FrequenctInterval) {
                            { ($frequencyInterval - 64) -ge 0 } {
                                $days[5] = "Saturday"
                                $frequencyInterval -= 64
                            }
                            { ($frequencyInterval - 32) -ge 0 } {
                                $days[4] = "Friday"
                                $frequencyInterval -= 32
                            }
                            { ($frequencyInterval - 16) -ge 0 } {
                                $days[3] = "Thursday"
                                $frequencyInterval -= 16
                            }
                            { ($frequencyInterval - 8) -ge 0 } {
                                $days[2] = "Wednesday"
                                $frequencyInterval -= 8
                            }
                            { ($frequencyInterval - 4) -ge 0 } {
                                $days[1] = "Tuesday"
                                $frequencyInterval -= 4
                            }
                            { ($frequencyInterval - 2) -ge 0 } {
                                $days[0] = "Monday"
                                $frequencyInterval -= 2
                            }
                            { ($frequencyInterval - 1) -ge 0 } {
                                $days[6] = "Sunday"
                                $frequencyInterval -= 1
                            }
                        }

                    }

                    # Add the days to the description by selecting the days and exploding the array
                    $description += ($days | Where-Object { $_ -ne $false }) -join ", "
                    $description += " "

                }

                # Monthly
                { $_ -in 16, "Monthly" } {
                    # Check if it's for one or more months
                    if ($currentschedule.FrequencyRecurrenceFactor -eq 1) {
                        $description += "month "
                    } elseif ($currentschedule.FrequencyRecurrenceFactor -gt 1) {
                        $description += "$($currentschedule.FrequencyRecurrenceFactor) month(s) "
                    }

                    # Add the interval
                    $description += "on day $($currentschedule.FrequencyInterval) of that month "
                }

                # Monthly relative
                { $_ -in 32, "MonthlyRelative" } {
                    # Check for the relative day
                    switch ($currentschedule.FrequencyRelativeIntervals) {
                        { $_ -in 1, "First" } { $description += "first " }
                        { $_ -in 2, "Second" } { $description += "second " }
                        { $_ -in 4, "Third" } { $description += "third " }
                        { $_ -in 8, "Fourth" } { $description += "fourth " }
                        { $_ -in 16, "Last" } { $description += "last " }
                    }

                    # Get the relative day of the week
                    switch ($currentschedule.FrequencyInterval) {
                        1 { $description += "Sunday " }
                        2 { $description += "Monday " }
                        3 { $description += "Tuesday " }
                        4 { $description += "Wednesday " }
                        5 { $description += "Thursday " }
                        6 { $description += "Friday " }
                        7 { $description += "Saturday " }
                        8 { $description += "Day " }
                        9 { $description += "Weekday " }
                        10 { $description += "Weekend day " }
                    }

                    $description += "of every $($currentschedule.FrequencyRecurrenceFactor) month(s) "

                }
            }

            # Check the frequency type
            if ($currentschedule.FrequencyTypes -notin 64, 128) {

                # Check the subday types for minutes or hours i.e.
                if ($currentschedule.FrequencySubDayInterval -in 0, 1) {
                    $description += "at $startTime. "
                } else {

                    switch ($currentschedule.FrequencySubDayTypes) {
                        { $_ -in 2, "Seconds" } { $description += "every $($currentschedule.FrequencySubDayInterval) second(s) " }
                        { $_ -in 4, "Minutes" } { $description += "every $($currentschedule.FrequencySubDayInterval) minute(s) " }
                        { $_ -in 8, "Hours" } { $description += "every $($currentschedule.FrequencySubDayInterval) hour(s) " }
                    }

                    $description += "between $startTime and $endTime. "
                }

                # Check if an end date has been given
                if ($currentschedule.ActiveEndDate.Year -eq 9999) {
                    $description += "Schedule will be used starting on $startDate."
                } else {
                    $description += "Schedule will used between $startDate and $endDate."
                }
            }

            return $description
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "$($server.Edition) does not support SQL Server Agent. Skipping $server." -Continue
            }

            $scheduleCollection = @()

            if ($Schedule -or $ScheduleUid -or $Id) {
                if ($Schedule) {
                    $scheduleCollection += $server.JobServer.SharedSchedules | Where-Object { $_.Name -in $Schedule }
                }

                if ($ScheduleUid) {
                    $scheduleCollection += $server.JobServer.SharedSchedules | Where-Object { $_.ScheduleUid -in $ScheduleUid }
                }

                if ($Id) {
                    $scheduleCollection += $server.JobServer.SharedSchedules | Where-Object { $_.Id -in $Id }
                }
            } else {
                $scheduleCollection = $server.JobServer.SharedSchedules
            }

            $defaults = "ComputerName", "InstanceName", "SqlInstance", "Name as ScheduleName", "ActiveEndDate", "ActiveEndTimeOfDay", "ActiveStartDate", "ActiveStartTimeOfDay", "DateCreated", "FrequencyInterval", "FrequencyRecurrenceFactor", "FrequencyRelativeIntervals", "FrequencySubDayInterval", "FrequencySubDayTypes", "FrequencyTypes", "IsEnabled", "JobCount", "Description", "ScheduleUid"

            foreach ($currentschedule in $scheduleCollection) {
                $description = Get-ScheduleDescription -CurrentSchedule $currentschedule

                $currentschedule | Add-Member -Type NoteProperty -Name ComputerName -Value $server.ComputerName
                $currentschedule | Add-Member -Type NoteProperty -Name InstanceName -Value $server.ServiceName
                $currentschedule | Add-Member -Type NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                $currentschedule | Add-Member -Type NoteProperty -Name Description -Value $description

                Select-DefaultView -InputObject $currentschedule -Property $defaults
            }
        }
    }
}