function Find-DbaDbGrowthEvent {
    <#
    .SYNOPSIS
        Retrieves database auto-growth and auto-shrink events from the SQL Server Default Trace

    .DESCRIPTION
        Queries the SQL Server Default Trace to identify when database files have automatically grown or shrunk, providing detailed timing and size change information essential for performance troubleshooting and capacity planning. This function helps DBAs investigate unexpected performance slowdowns caused by auto-growth events, analyze storage growth patterns to optimize initial file sizing, and track which applications or processes are triggering unplanned database expansions. Returns comprehensive details including the exact time of each event, size change in MB, duration, and the application/user that caused the growth, so you don't have to manually parse trace files or write custom T-SQL queries.

        The following events are included:
        92 - Data File Auto Grow
        93 - Log File Auto Grow
        94 - Data File Auto Shrink
        95 - Log File Auto Shrink

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for growth events. Accepts wildcards for pattern matching.
        Use this to focus on specific databases when investigating growth patterns or troubleshooting performance issues.
        If not specified, searches all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specified databases from the growth event search. Accepts wildcards for pattern matching.
        Useful when you want to skip system databases like tempdb or exclude databases with known frequent growth events.
        Commonly used with tempdb, master, model, and msdb to focus on user databases only.

    .PARAMETER EventType
        Filters results to show only specific types of database size change events.
        Use 'Growth' to identify when files expanded automatically, which can indicate undersized initial allocations or unexpected data volume increases.
        Use 'Shrink' to find auto-shrink events that may be causing performance problems due to file fragmentation.

        Allowed values: Growth, Shrink

    .PARAMETER FileType
        Filters results to show only data file or log file growth events.
        Use 'Data' when investigating storage capacity issues or unexpected table growth patterns.
        Use 'Log' when troubleshooting transaction log growth, often caused by long-running transactions or delayed log backups.

        Allowed values: Data, Log

    .PARAMETER UseLocalTime
        Returns timestamps in the SQL Server instance's local time zone instead of converting to UTC.
        Use this when correlating growth events with local application schedules, maintenance windows, or business hours.
        By default, times are converted to UTC for consistency across multiple time zones.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AutoGrow, Database, Lookup
        Author: Aaron Nelson

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Query Extracted from SQL Server Management Studio (SSMS) 2016.

    .LINK
        https://dbatools.io/Find-DbaDbGrowthEvent

    .OUTPUTS
        PSCustomObject

        Returns one object per database auto-growth or auto-shrink event found in the SQL Server Default Trace. The specific events returned depend on the -EventType and -FileType parameters.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name where the SQL Server instance is running
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - EventClass: The trace event class (92 = Data File Auto Grow, 93 = Log File Auto Grow, 94 = Data File Auto Shrink, 95 = Log File Auto Shrink)
        - DatabaseName: The name of the database that experienced the growth/shrink event
        - Filename: The path and name of the database file that was resized
        - Duration: The duration of the event in milliseconds
        - StartTime: The date and time when the event started (UTC by default, local time if -UseLocalTime is specified)
        - EndTime: The date and time when the event ended (UTC by default, local time if -UseLocalTime is specified)
        - ChangeInSize: The size change during the event in megabytes (MB)
        - ApplicationName: The application that triggered the growth event
        - HostName: The host name of the client that triggered the event

        Additional properties available (accessible with Select-Object *):
        - DatabaseId: The numeric database identifier from sys.databases
        - SessionLoginName: The SQL login name of the session that triggered the event
        - SPID: The SQL Server session ID (SPID) of the process that caused the event
        - OrderRank: Internal ranking value used for trace file rotation ordering

    .EXAMPLE
        PS C:\> Find-DbaDbGrowthEvent -SqlInstance localhost

        Returns any database AutoGrow events in the Default Trace with UTC time for the instance for every database on the localhost instance.

    .EXAMPLE
        PS C:\> Find-DbaDbGrowthEvent -SqlInstance localhost -UseLocalTime

        Returns any database AutoGrow events in the Default Trace with the local time of the instance for every database on the localhost instance.

    .EXAMPLE
        PS C:\> Find-DbaDbGrowthEvent -SqlInstance ServerA\SQL2016, ServerA\SQL2014

        Returns any database AutoGrow events in the Default Traces for every database on ServerA\sql2016 & ServerA\SQL2014.

    .EXAMPLE
        PS C:\> Find-DbaDbGrowthEvent -SqlInstance ServerA\SQL2016 | Format-Table -AutoSize -Wrap

        Returns any database AutoGrow events in the Default Trace for every database on the ServerA\SQL2016 instance in a table format.

    .EXAMPLE
        PS C:\> Find-DbaDbGrowthEvent -SqlInstance ServerA\SQL2016 -EventType Shrink

        Returns any database Auto Shrink events in the Default Trace for every database on the ServerA\SQL2016 instance.

    .EXAMPLE
        PS C:\> Find-DbaDbGrowthEvent -SqlInstance ServerA\SQL2016 -EventType Growth -FileType Data

        Returns any database Auto Growth events on data files in the Default Trace for every database on the ServerA\SQL2016 instance.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet('Growth', 'Shrink')]
        [string]$EventType,
        [ValidateSet('Data', 'Log')]
        [string]$FileType,
        [switch]$UseLocalTime,
        [switch]$EnableException
    )

    begin {
        $eventClass = New-Object System.Collections.ArrayList
        92..95 | ForEach-Object { $null = $eventClass.Add($_) }

        if (Test-Bound 'EventType', 'FileType') {
            switch ($FileType) {
                'Data' {
                    <# should only contain events for data: 92 (grow), 94 (shrink) #>
                    $eventClass.Remove(93)
                    $eventClass.Remove(95)
                }
                'Log' {
                    <# should only contain events for log: 93 (grow), 95 (shrink) #>
                    $eventClass.Remove(92)
                    $eventClass.Remove(94)
                }
            }
            switch ($EventType) {
                'Growth' {
                    <# should only contain events for growth: 92 (data), 93 (log) #>
                    $eventClass.Remove(94)
                    $eventClass.Remove(95)
                }
                'Shrink' {
                    <# should only contain events for shrink: 94 (data), 95 (log) #>
                    $eventClass.Remove(92)
                    $eventClass.Remove(93)
                }
            }
        }

        $eventClassFilter = $eventClass -join ","

        $sqlTemplate = "
            BEGIN TRY
                IF (SELECT CONVERT(INT,[value_in_use]) FROM sys.configurations WHERE [name] = 'default trace enabled' ) = 1
                    BEGIN
                        DECLARE @curr_tracefilename VARCHAR(500);
                        DECLARE @base_tracefilename VARCHAR(500);
                        DECLARE @indx INT;

                        SELECT @curr_tracefilename = [path]
                        FROM sys.traces
                        WHERE is_default = 1 ;

                        SET @curr_tracefilename = REVERSE(@curr_tracefilename);
                        SELECT @indx  = PATINDEX('%\%', @curr_tracefilename);
                        SET @curr_tracefilename = REVERSE(@curr_tracefilename);
                        SET @base_tracefilename = LEFT( @curr_tracefilename,LEN(@curr_tracefilename) - @indx) + '\log.trc';

                        SELECT
                            SERVERPROPERTY('MachineName') AS ComputerName,
                            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                            SERVERPROPERTY('ServerName') AS SqlInstance,
                            CONVERT(INT,(DENSE_RANK() OVER (ORDER BY [StartTime] DESC))%2) AS OrderRank,
                                CONVERT(INT, [EventClass]) AS EventClass,
                            [DatabaseName],
                            (SELECT database_id FROM sys.databases WHERE Name = [DatabaseName]) AS DatabaseId,
                            [Filename],
                            CONVERT(INT,(Duration/1000)) AS Duration,
                            $(if (-not $UseLocalTime) { "
                            DATEADD (MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), [StartTime]) AS StartTime,  -- Convert to UTC time
                            DATEADD (MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), [EndTime]) AS EndTime,  -- Convert to UTC time"
                            }
                            else { "
                            [StartTime] AS StartTime,
                            [EndTime] AS EndTime,"
                            })
                            ([IntegerData]*8.0/1024) AS ChangeInSize,
                            ApplicationName,
                            HostName,
                            SessionLoginName,
                            SPID
                        FROM ::fn_trace_gettable( @base_tracefilename, DEFAULT )
                        WHERE
                            [EventClass] IN ($eventClassFilter)
                            AND [DatabaseName] IN (_DatabaseList_)
                        ORDER BY [StartTime] DESC;
                    END
                ELSE
                    SELECT
                        SERVERPROPERTY('MachineName') AS ComputerName,
                        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                        SERVERPROPERTY('ServerName') AS SqlInstance,
                        -100 AS [OrderRank],
                        -1 AS [OrderRank],
                        0 AS [EventClass],
                        0 [DatabaseName],
                        0 AS [Filename],
                        0 AS [Duration],
                        0 AS [StartTime],
                        0 AS [EndTime],
                        0 AS ChangeInSize,
                        0 AS [ApplicationName],
                        0 AS [HostName],
                        0 AS [SessionLoginName],
                        0 AS [SPID]
            END    TRY
            BEGIN CATCH
                SELECT
                    SERVERPROPERTY('MachineName') AS ComputerName,
                    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                    SERVERPROPERTY('ServerName') AS SqlInstance,
                    -100 AS [OrderRank],
                    -100 AS [OrderRank],
                    ERROR_NUMBER() AS [EventClass],
                    ERROR_SEVERITY() AS [DatabaseName],
                    ERROR_STATE() AS [Filename],
                    ERROR_MESSAGE() AS [Duration],
                    1 AS [StartTime],
                    1 AS [EndTime],
                    1 AS [ChangeInSize],
                    1 AS [ApplicationName],
                    1 AS [HostName],
                    1 AS [SessionLoginName],
                    1 AS [SPID]
            END CATCH"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            #Create dblist name in 'db1', 'db2' format
            $dbsList = "'$($($dbs | ForEach-Object {$_.Name}) -join "','")'"
            Write-Message -Level Verbose -Message "Executing query against $dbsList on $instance"

            $sql = $sqlTemplate -replace '_DatabaseList_', $dbsList
            Write-Message -Level Debug -Message "Executing SQL Statement:`n $sql"

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'EventClass', 'DatabaseName', 'Filename', 'Duration', 'StartTime', 'EndTime', 'ChangeInSize', 'ApplicationName', 'HostName'

            try {
                Select-DefaultView -InputObject $server.Query($sql) -Property $defaults
            } catch {
                Stop-Function -Message "Issue collecting data on $server" -Target $server -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue
            }
        }
    }
}