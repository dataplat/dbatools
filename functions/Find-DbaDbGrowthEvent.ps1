#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Find-DbaDbGrowthEvent {
    <#
        .SYNOPSIS
            Finds any database AutoGrow events in the Default Trace.

        .DESCRIPTION
            Finds any database AutoGrow events in the Default Trace.

            The following events are included:
                92 - Data File Auto Grow
                93 - Log File Auto Grow
                94 - Data File Auto Shrink
                95 - Log File Auto Shrink

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            The database(s) to exclude - this list is auto-populated from the server

        .PARAMETER EventType
            Provide a filter on growth event type to filter the results.

            Allowed values: Growth, Shrink

        .PARAMETER FileType
            Provide a filter on file type to filter the results.

            Allowed vaules: Data, Log

        .PARAMETER UseLocalTime
            Return the local time of the instance instead of converting to UTC.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: AutoGrow,Growth,Database
            Author: Aaron Nelson
            Query Extracted from SQL Server Management Studio (SSMS) 2016.

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Find-DbaDatabaseGrowthEvent

        .EXAMPLE
            Find-DbaDatabaseGrowthEvent -SqlInstance localhost

            Returns any database AutoGrow events in the Default Trace with UTC time for the instance for every database on the localhost instance.

        .EXAMPLE
            Find-DbaDatabaseGrowthEvent -SqlInstance localhost -UseLocalTime

            Returns any database AutoGrow events in the Default Trace with the local time of the instance for every database on the localhost instance.

        .EXAMPLE
            Find-DbaDatabaseGrowthEvent -SqlInstance ServerA\SQL2016, ServerA\SQL2014

            Returns any database AutoGrow events in the Default Traces for every database on ServerA\sql2016 & ServerA\SQL2014.

        .EXAMPLE
            Find-DbaDatabaseGrowthEvent -SqlInstance ServerA\SQL2016 | Format-Table -AutoSize -Wrap

            Returns any database AutoGrow events in the Default Trace for every database on the ServerA\SQL2016 instance in a table format.

        .EXAMPLE
            Find-DbaDatabaseGrowthEvent -SqlInstance ServerA\SQL2016 -EventType Shrink

            Returns any database Auto Shrink events in the Default Trace for every database on the ServerA\SQL2016 instance.

        .EXAMPLE
            Find-DbaDatabaseGrowthEvent -SqlInstance ServerA\SQL2016 -EventType Growth -FileType Data

            Returns any database Auto Growth events on data files in the Default Trace for every database on the ServerA\SQL2016 instance.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet('Growth', 'Shrink')]
        [string]$EventType,
        [ValidateSet('Data', 'Log')]
        [string]$FileType,
        [switch]$UseLocalTime,
        [Alias('Silent')]
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

        $sql = "
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
                        FROM::fn_trace_gettable( @base_tracefilename, DEFAULT )
                        WHERE
                            [EventClass] IN ($eventClassFilter)
                            AND [ServerName] = @@SERVERNAME
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
            END	TRY
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

        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Find-DbaDatabaseGrowthEvent
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

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            #Create dblist name in 'bd1', 'db2' format
            $dbsList = "'$($($dbs | ForEach-Object {$_.Name}) -join "','")'"
            Write-Message -Level Verbose -Message "Executing query against $dbsList on $instance"

            $sql = $sql -replace '_DatabaseList_', $dbsList
            Write-Message -Level Debug -Message "Executing SQL Statement:`n $sql"

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'EventClass', 'DatabaseName', 'Filename', 'Duration', 'StartTime', 'EndTime', 'ChangeInSize', 'ApplicationName', 'HostName'

            try {
                Select-DefaultView -InputObject $server.Query($sql) -Property $defaults
            }
            catch {
                Stop-Function -Message "Issue collecting data on $server" -Target $server -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException.InnerException -Continue
            }
        }
    }
}
