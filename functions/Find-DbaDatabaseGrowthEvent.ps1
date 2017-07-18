function Find-DbaDatabaseGrowthEvent {
	<#
		.SYNOPSIS
			Finds any database AutoGrow events in the Default Trace.

		.DESCRIPTION
			Finds any database AutoGrow events in the Default Trace.

		.PARAMETER SqlInstance
			The SQL Server that you're connecting to.

		.PARAMETER SqlCredential
			SqlCredential object used to connect to the SQL Server as a different user.

		.PARAMETER Database
			The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

		.PARAMETER ExcludeDatabase
			The database(s) to exclude - this list is autopopulated from the server

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: AutoGrow
			Original Author: Aaron Nelson
			Query Extracted from SQL Server Management Studio (SSMS) 2016.

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Find-DbaDatabaseGrowthEvent

		.EXAMPLE
			Find-DBADatabaseGrowthEvent -SqlInstance localhost

			Returns any database AutoGrow events in the Default Trace for every database on the localhost instance.

		.EXAMPLE
			Find-DBADatabaseGrowthEvent -SqlInstance ServerA\SQL2016, ServerA\SQL2014

			Returns any database AutoGrow events in the Default Traces for every database on ServerA\sql2016 & ServerA\SQL2014.

		.EXAMPLE
			Find-DBADatabaseGrowthEvent -SqlInstance ServerA\SQL2016 | Format-Table -AutoSize -Wrap

			Returns any database AutoGrow events in the Default Trace for every database on the ServerA\SQL2016 instance in a table format.
	#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[switch]$Silent
	)

	begin {
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
							DATEADD (MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), [StartTime]) AS StartTime,  -- Convert to UTC time
							DATEADD (MINUTE, DATEDIFF(MINUTE, GETDATE(), GETUTCDATE()), [EndTime]) AS EndTime,  -- Convert to UTC time
							([IntegerData]*8.0/1024) AS ChangeInSize
						FROM::fn_trace_gettable( @base_tracefilename, DEFAULT )
						WHERE
							[EventClass] >= 92
							AND [EventClass] <= 95
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
						0 AS ChangeInSize
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
					1 AS [ChangeInSize]
			END CATCH"
	}
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Connecting to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Write-Message -Level Warning -Message "Can't connect to $instance. Moving on."
				continue
			}

			$dbs = $server.Databases

			if ($Database) {
				$dbs = $dbs | Where-Object Name -in $Database
			}

			if ($ExcludeDatabase) {
				$dbs = $dbs | Where-Object Name -notin $ExcludeDatabase
			}

			#Create dblist name in 'bd1', 'db2' format
			$dbsList = "'$($($dbs | ForEach-Object {$_.Name}) -join "','")'"
			Write-Message -Level Verbose -Message "Executing query against $dbsList on $instance"
			
			$sql = $sql -replace '_DatabaseList_', $dbsList
			Write-Message -Level Debug -Message $sql

			$props = 'ComputerName', 'InstanceName', 'SqlInstance', 'EventClass', 'DatabaseName', 'Filename', 'Duration', 'StartTime', 'EndTime', 'ChangeInSize'

			Select-DefaultView -InputObject $server.Query($sql) -Property $props
		}
	}
}

