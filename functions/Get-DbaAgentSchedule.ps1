function Get-DbaAgentSchedule {
    <#
    .SYNOPSIS
    Returns all SQL Agent Shared Schedules on a SQL Server Agent.

    .DESCRIPTION
    This function returns SQL Agent Shared Schedules.

    .PARAMETER SqlInstance
    SqlInstance name or SMO object representing the SQL Server to connect to.
    This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
    PSCredential object to connect as. If not specified, current Windows login will be used.

    .PARAMETER Schedule
    Parameter to filter the schedules returned

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Agent, Schedule
    Author: Chris McKeown (@devopsfu), http://www.devopsfu.com

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Get-DbaAgentSchedule

    .EXAMPLE
    Get-DbaAgentSchedule -SqlInstance localhost

    Returns all SQL Agent Shared Schedules on the local default SQL Server instance

    .EXAMPLE
    Get-DbaAgentSchedule -SqlInstance localhost, sql2016

    Returns all SQL Agent Shared Schedules for the local and sql2016 SQL Server instances
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "Instance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Schedules")]
        [object[]]$Schedule,
        [PSCredential]$SqlCredential,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        function Get-ScheduleDescription {
            param (
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [object]$Schedule

            )

            # Get the culture to make sure the right date and time format is displayed
            $datetimeFormat = (Get-culture).DateTimeFormat

            # Set the intial description
            $description = ""

            # Get the date and time values
            $startDate = Get-Date $Schedule.ActiveStartDate -format $datetimeFormat.ShortDatePattern
            $startTime = Get-Date ($Schedule.ActiveStartTimeOfDay.ToString()) -format $datetimeFormat.LongTimePattern
            $endDate = Get-Date $Schedule.ActiveEndDate -format $datetimeFormat.ShortDatePattern
            $endTime = Get-Date ($Schedule.ActiveEndTimeOfDay.ToString()) -format $datetimeFormat.LongTimePattern

            # Start setting the description based on the frequency type
            switch ($schedule.FrequencyTypes) {
                {($_ -eq 1) -or ($_ -eq "Once")} { $description += "Occurs on $startDate at $startTime" }
                {($_ -in 4, 8, 16, 32) -or ($_ -in "Daily", "Weekly", "Monthly")} { $description += "Occurs every "}
                {($_ -eq 64) -or ($_ -eq "AutoStart")} {$description += "Start automatically when SQL Server Agent starts "}
                {($_ -eq 128) -or ($_ -eq "OnIdle")} {$description += "Start whenever the CPUs become idle"}
            }

            # Check the frequency types for daily or weekly i.e.
            switch ($schedule.FrequencyTypes) {
                # Daily
                {$_ -in 4, "Daily"} {
                    if ($Schedule.FrequencyInterval -eq 1) {
                        $description += "day "
                    }
                    elseif ($Schedule.FrequencyInterval -gt 1) {
                        $description += "$($Schedule.FrequencyInterval) day(s) "
                    }
                }

                # Weekly
                {$_ -in 8, "Weekly"} {
                    # Check if it's for one or more weeks
                    if ($Schedule.FrequencyRecurrenceFactor -eq 1) {
                        $description += "week on "
                    }
                    elseif ($Schedule.FrequencyRecurrenceFactor -gt 1) {
                        $description += "$($Schedule.FrequencyRecurrenceFactor) week(s) on "
                    }

                    # Save the interval for the loop
                    $frequencyInterval = $Schedule.FrequencyInterval

                    # Create the array to hold the days
                    $days = ($false, $false, $false, $false, $false, $false, $false)

                    # Loop through the days
                    while ($frequencyInterval -gt 0) {

                        switch ($FrequenctInterval) {
                            {($frequencyInterval - 64) -ge 0} {
                                $days[5] = "Saturday"
                                $frequencyInterval -= 64
                            }
                            {($frequencyInterval - 32) -ge 0} {
                                $days[4] = "Friday"
                                $frequencyInterval -= 32
                            }
                            {($frequencyInterval - 16) -ge 0} {
                                $days[3] = "Thursday"
                                $frequencyInterval -= 16
                            }
                            {($frequencyInterval - 8) -ge 0} {
                                $days[2] = "Wednesday"
                                $frequencyInterval -= 8
                            }
                            {($frequencyInterval - 4) -ge 0} {
                                $days[1] = "Tuesday"
                                $frequencyInterval -= 4
                            }
                            {($frequencyInterval - 2) -ge 0} {
                                $days[0] = "Monday"
                                $frequencyInterval -= 2
                            }
                            {($frequencyInterval - 1) -ge 0} {
                                $days[6] = "Sunday"
                                $frequencyInterval -= 1
                            }
                        }

                    }

                    # Add the days to the description by selecting the days and exploding the array
                    $description += ($days | Where-Object {$_ -ne $false}) -join ", "
                    $description += " "

                }

                # Monthly
                {$_ -in 16, "Monthly"} {
                    # Check if it's for one or more months
                    if ($Schedule.FrequencyRecurrenceFactor -eq 1) {
                        $description += "month "
                    }
                    elseif ($Schedule.FrequencyRecurrenceFactor -gt 1) {
                        $description += "$($Schedule.FrequencyRecurrenceFactor) month(s) "
                    }

                    # Add the interval
                    $description += "on day $($Schedule.FrequencyInterval) of that month "
                }

                # Monthly relative
                {$_ -in 32, "MonthlyRelative"} {
                    # Check for the relative day
                    switch ($Schedule.FrequencyRelativeIntervals) {
                        {$_ -in 1, "First"} {$description += "first "}
                        {$_ -in 2, "Second"} {$description += "second "}
                        {$_ -in 4, "Third"} {$description += "third "}
                        {$_ -in 8, "Fourth"} {$description += "fourth "}
                        {$_ -in 16, "Last"} {$description += "last "}
                    }

                    # Get the relative day of the week
                    switch ($Schedule.FrequencyInterval) {
                        1 { $description += "Sunday "}
                        2 { $description += "Monday "}
                        3 { $description += "Tuesday "}
                        4 { $description += "Wednesday "}
                        5 { $description += "Thursday "}
                        6 { $description += "Friday "}
                        7 { $description += "Saturday "}
                        8 { $description += "Day "}
                        9 { $description += "Weekday "}
                        10 { $description += "Weekend day "}
                    }

                    $description += "of every $($Schedule.FrequencyRecurrenceFactor) month(s) "

                }
            }

            # Check the frequency type
            if ($schedule.FrequencyTypes -notin 64, 128) {

                # Check the subday types for minutes or hours i.e.
                if ($schedule.FrequencySubDayInterval -in 0, 1) {
                    $description += "at $startTime. "
                }
                else {

                    switch ($Schedule.FrequencySubDayTypes) {
                        {$_ -in 2, "Seconds"} { $description += "every $($schedule.FrequencySubDayInterval) second(s) "}
                        {$_ -in 4, "Minutes"} {$description += "every $($schedule.FrequencySubDayInterval) minute(s) " }
                        {$_ -in 8, "Hours"} { $description += "every $($schedule.FrequencySubDayInterval) hour(s) " }
                    }

                    $description += "between $startTime and $endTime. "
                }

                # Check if an end date has been given
                if ($Schedule.ActiveEndDate.Year -eq 9999) {
                    $description += "Schedule will be used starting on $startDate."
                }
                else {
                    $description += "Schedule will used between $startDate and $endDate."
                }
            }

            return $description
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "$($server.Edition) does not support SQL Server Agent. Skipping $server." -Continue
            }

            if ($Schedule) {
                $scheduleCollection = $server.JobServer.SharedSchedules | Where-Object { $_.Name -in $Schedule }
            }
            else {
                $scheduleCollection = $server.JobServer.SharedSchedules
            }

        }

        $defaults = "ComputerName", "InstanceName", "SqlInstance", "Name as ScheduleName", "ActiveEndDate", "ActiveEndTimeOfDay", "ActiveStartDate", "ActiveStartTimeOfDay", "DateCreated", "FrequencyInterval", "FrequencyRecurrenceFactor", "FrequencyRelativeIntervals", "FrequencySubDayInterval", "FrequencySubDayTypes", "FrequencyTypes", "IsEnabled", "JobCount", "Description"

        foreach ($schedule in $scheduleCollection) {
            $description = Get-ScheduleDescription -Schedule $schedule

            Add-Member -Force -InputObject $schedule -MemberType NoteProperty ComputerName -value $server.NetName
            Add-Member -Force -InputObject $schedule -MemberType NoteProperty InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $schedule -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $schedule -MemberType NoteProperty Description -Value $description

            Select-DefaultView -InputObject $schedule -Property $defaults
        }

    }
}
