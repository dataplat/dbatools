function Get-DbaQueryStoreConfig {
<#
.SYNOPSIS
Get the Query Store configuration for Query Store enabled databases.

.DESCRIPTION
Retrieves and returns the Query Store configuration for every database that has the Query Store feature enabled.

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
SqlCredential object used to connect to the SQL Server as a different user.

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.NOTES
Tags: QueryStore
Author: Enrico van de Laar ( @evdlaar )

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-QueryStoreConfig

.EXAMPLE
Get-DbaQueryStoreConfig -SqlInstance ServerA\sql

Returns Query Store configuration settings for every database on the ServerA\sql instance.

.EXAMPLE
Get-DbaQueryStoreConfig -SqlInstance ServerA\sql | Where-Object {$_.ActualState -eq "ReadWrite"}

Returns the Query Store configuration for all databases on ServerA\sql where the Query Store feature is in Read/Write mode.

.EXAMPLE
Get-DbaQueryStoreConfig -SqlInstance localhost | format-table -AutoSize -Wrap

Returns Query Store configuration settings for every database on the ServerA\sql instance inside a table format.

#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase
	)
	process
	{
		foreach ($instance in $SqlInstance)
		{
			Write-Verbose "Connecting to $instance"
			try
			{
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $instance. Moving on."
				continue
			}

			if ($server.VersionMajor -lt 13)
			{
				Write-Warning "The SQL Server Instance ($instance) has a lower SQL Server version than SQL Server 2016. Skipping server."
				continue
			}

			# We have to exclude all the system databases since they cannot have the Query Store feature enabled
			$dbs = Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -NoSystemDb

			if ($Database)
			{
				$dbs = $dbs | Where-Object Name -In $Database
			}

			if ($ExcludeDatabase)
			{
				$dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
			}

			foreach ($db in $dbs)
			{
				Write-Verbose "Processing $db on $instance"

				if ($db.IsAccessible -eq $false)
				{
					Write-Warning "The database $db on server $instance is not accessible. Skipping database."
					Continue
				}

				[pscustomobject]@{
					Instance = $instance
					Database = $db.Name
					ActualState = $db.QueryStoreOptions.ActualState
					FlushInterval = $db.QueryStoreOptions.DataFlushIntervalInSeconds
					CollectionInterval = $db.QueryStoreOptions.StatisticsCollectionIntervalInMinutes
					MaxSize = $db.QueryStoreOptions.MaxStorageSizeInMB
					CurrentSize = $db.QueryStoreOptions.CurrentStorageSizeInMB
					CaptureMode = $db.QueryStoreOptions.QueryCaptureMode
					CleanupMode = $db.QueryStoreOptions.SizeBasedCleanupMode
					StaleQueryThreshold = $db.QueryStoreOptions.StaleQueryThresholdInDays
				}
			}
		}
	}
}
