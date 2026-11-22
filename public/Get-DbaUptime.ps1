function Get-DbaUptime {
    <#
    .SYNOPSIS
        Retrieves uptime information for SQL Server instances and their hosting Windows servers

    .DESCRIPTION
        This function determines the SQL Server start time from the tempdb creation date, lets the instance measure its own uptime, and calculates Windows server uptime using CIM/WMI calls to get the last boot time. Essential for monitoring system stability, troubleshooting unexpected restarts, and generating compliance reports that require uptime documentation. Returns both raw TimeSpan objects for calculations and formatted strings for reporting, covering both the SQL Server service and the underlying Windows host.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Specifies Windows credentials to connect to the hosting server for retrieving Windows boot time and uptime information.
        Use this when you need different credentials to access the Windows server than your current PowerShell session, such as when querying servers in different domains or when running under a service account that lacks WMI access.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: CIM, Instance, Utility
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaUptime

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance containing uptime information for both SQL Server and its hosting Windows server.

        Properties:
        - ComputerName: The Windows server computer name (from DNS resolution)
        - InstanceName: The SQL Server instance name
        - SqlServer: The full SQL Server instance name
        - SqlStartTime: DateTime when SQL Server was started (based on tempdb creation date)
        - SqlUptime: TimeSpan object showing SQL Server uptime duration, measured by the instance itself (sys.dm_os_sys_info). For a login without VIEW SERVER STATE it is counted from SqlStartTime up to the current time of the instance, with the offset that the time zone of the instance had at SqlStartTime, so that a daylight saving change since then counts. Before SQL Server 2022 the instance cannot name its time zone, and SqlStartTime is converted with the time zone of this computer, which is right when the instance is in the same time zone. SqlStartTime has no offset, so a start in the hour that repeats when the clocks go back counts as the second occurrence, in standard time; an instance that started in the first ran one change of the clocks (mostly an hour) longer than reported
        - SinceSqlStart: Formatted string of SQL Server uptime as "X days Y hours Z minutes A seconds"
        - WindowsBootTime: DateTime when the Windows server was last booted
        - WindowsUptime: TimeSpan object showing Windows server uptime duration
        - SinceWindowsBoot: Formatted string of Windows uptime as "X days Y hours Z minutes A seconds"

    .EXAMPLE
        PS C:\> Get-DbaUptime -SqlInstance SqlBox1\Instance2

        Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for the sqlexpress instance on winserver

    .EXAMPLE
        PS C:\> Get-DbaUptime -SqlInstance winserver\sqlexpress, sql2016

        Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for the sqlexpress instance on host winserver  and the default instance on host sql2016

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2014 | Get-DbaUptime

        Returns an object with SQL Server start time, uptime as TimeSpan object, uptime as a string, and Windows host boot time, host uptime as TimeSpan objects and host uptime as a string for every server listed in the Central Management Server on sql2014

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    begin {
        $nowutc = (Get-Date).ToUniversalTime()
    }
    process {
        # uses cim commands


        foreach ($instance in $SqlInstance) {
            if ($instance.Gettype().FullName -eq [System.Management.Automation.PSCustomObject] ) {
                $servername = $instance.SqlInstance
            } elseif ($instance.Gettype().FullName -eq [Microsoft.SqlServer.Management.Smo.Server]) {
                $servername = $instance.ComputerName
            } else {
                $servername = $instance.ComputerName;
            }

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Getting start times for $servername"
            #Get tempdb creation date
            [dbadatetime]$SQLStartTime = $server.Databases["tempdb"].CreateDate
            # The creation date of tempdb is a time in the local time of the instance, which cannot be compared with the clock
            # of this computer when the two are in different time zones. So the instance measures its uptime itself, in
            # milliseconds since its start, which neither a clock nor a daylight saving change can shift.
            try {
                $uptimeMilliseconds = $server.Query("SELECT ms_ticks - sqlserver_start_time_ms_ticks AS UptimeMilliseconds FROM sys.dm_os_sys_info").UptimeMilliseconds
                $SQLUptime = [timespan]::FromMilliseconds($uptimeMilliseconds)
            } catch {
                # sys.dm_os_sys_info needs VIEW SERVER STATE. Without it the uptime is counted up to the current time of the instance.
                # Both ends are local times of the instance, and a daylight saving change between them would shift the result by an
                # hour, so the start is converted to UTC with the offset its time zone had at that date, not with the offset of today.
                $sysInfoError = $_
                # Test-DbaFeatureSupport throws on an engine it has no rule for, which then gets the conversion that works on every engine.
                try {
                    $instanceNamesTimeZone = Test-DbaFeatureSupport -Server $server -Feature CurrentTimeZoneId
                } catch {
                    $instanceNamesTimeZone = $false
                }
                if ($instanceNamesTimeZone) {
                    # SQL Server 2022 and later name the time zone of the instance, and AT TIME ZONE applies the offset of the date it converts.
                    # The start is SqlStartTime itself, so that the uptime is always counted from the start the command reports.
                    Write-Message -Level Verbose -Message "Could not read sys.dm_os_sys_info on $servername, counting the uptime up to the current time of the instance in its time zone" -ErrorRecord $sysInfoError
                    $startTime = $server.Databases["tempdb"].CreateDate.ToString("yyyy-MM-ddTHH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    # A start in the hour that repeats when the clocks go back has no offset that tells its two occurrences apart, and
                    # AT TIME ZONE takes the first, with the offset before the change. Such a start counts as the second, in standard time,
                    # as .NET converts an ambiguous time and as the command did before. The second occurrence lies the change of the offset
                    # later, which the offset one day later gives, and the start repeats only when that time has the same local time.
                    $uptimeQuery = @"
DECLARE @timeZone nvarchar(256) = CURRENT_TIMEZONE_ID();
DECLARE @startTime datetime2(3) = CONVERT(datetime2(3), '$startTime', 126);
DECLARE @firstStart datetimeoffset(3) = @startTime AT TIME ZONE @timeZone;
DECLARE @secondStart datetimeoffset(3) = DATEADD(MINUTE, DATEPART(TZOFFSET, @firstStart) - DATEPART(TZOFFSET, DATEADD(DAY, 1, @startTime) AT TIME ZONE @timeZone), @firstStart) AT TIME ZONE @timeZone;
DECLARE @startRepeats bit = CASE WHEN CONVERT(datetime2(3), @secondStart) = @startTime AND @secondStart <> @firstStart THEN 1 ELSE 0 END;
SELECT DATEDIFF_BIG(MILLISECOND, CASE WHEN @startRepeats = 1 THEN @secondStart ELSE @firstStart END, SYSDATETIMEOFFSET()) AS UptimeMilliseconds,
       @startRepeats AS StartRepeats
"@
                    $uptimeResult = $server.Query($uptimeQuery)
                    $SQLUptime = [timespan]::FromMilliseconds($uptimeResult.UptimeMilliseconds)
                    if ($uptimeResult.StartRepeats) {
                        Write-Message -Level Verbose -Message "SqlStartTime $startTime of $servername lies in the hour that repeats when the clocks go back, counting it as the second occurrence in standard time. Had the instance started in the first, it ran one change of the clocks longer"
                    }
                } else {
                    # Before SQL Server 2022 the instance cannot name its time zone. The time zone of this computer converts the start, as
                    # the command always did, which is right when the instance is in the same time zone. Only the end is the clock of the instance.
                    Write-Message -Level Verbose -Message "Could not read sys.dm_os_sys_info on $servername, counting the uptime up to the current time of the instance in the time zone of this computer" -ErrorRecord $sysInfoError
                    $serverUtcTime = $server.Query("SELECT SYSUTCDATETIME() AS ServerUtcTime").ServerUtcTime
                    # ToUniversalTime counts a start in the hour that repeats when the clocks go back as the second occurrence, in standard time.
                    $SQLUptime = New-TimeSpan -Start $SQLStartTime.ToUniversalTime() -End $serverUtcTime
                    if ([System.TimeZoneInfo]::Local.IsAmbiguousTime($server.Databases["tempdb"].CreateDate)) {
                        Write-Message -Level Verbose -Message "SqlStartTime $SQLStartTime of $servername lies in the hour that repeats when the clocks go back, counting it as the second occurrence in standard time. Had the instance started in the first, it ran one change of the clocks longer"
                    }
                }
            }
            $SQLUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($SQLUptime.Days), $($SQLUptime.Hours), $($SQLUptime.Minutes), $($SQLUptime.Seconds)

            $WindowsServerName = (Resolve-DbaNetworkName $servername -Credential $Credential).FullComputerName

            try {
                Write-Message -Level Verbose -Message "Getting WinBootTime via CimInstance for $servername"
                $WinBootTime = (Get-DbaOperatingSystem -ComputerName $windowsServerName -Credential $Credential -ErrorAction SilentlyContinue).LastBootTime
                $WindowsUptime = New-TimeSpan -start $WinBootTime.ToUniversalTime() -end $nowutc
                $WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
            } catch {
                try {
                    Write-Message -Level Verbose -Message "Getting WinBootTime via CimInstance DCOM"
                    $CimOption = New-CimSessionOption -Protocol DCOM
                    $CimSession = New-CimSession -Credential:$Credential -ComputerName $WindowsServerName -SessionOption $CimOption
                    [dbadatetime]$WinBootTime = ($CimSession | Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
                    $WindowsUptime = New-TimeSpan -start $WinBootTime.ToUniversalTime() -end $nowutc
                    $WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
                } catch {
                    Stop-Function -Message "Failure getting WinBootTime" -ErrorRecord $_ -Target $instance -Continue
                }
            }

            [PSCustomObject]@{
                ComputerName     = $WindowsServerName
                InstanceName     = $server.ServiceName
                SqlServer        = $server.Name
                SqlUptime        = $SQLUptime
                WindowsUptime    = $WindowsUptime
                SqlStartTime     = $SQLStartTime
                WindowsBootTime  = $WinBootTime
                SinceSqlStart    = $SQLUptimeString
                SinceWindowsBoot = $WindowsUptimeString
            }
        }
    }
}