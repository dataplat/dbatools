Function Get-DbaBackupHistory
{
<#
.SYNOPSIS
Returns backup history details for databases on a SQL Server
	
.DESCRIPTION
Returns backup history details for some or all databases on a SQL Server. 

You can even get detailed information (including file path) for latest full, differential and log files.
	
Reference: http://www.sqlhub.com/2011/07/find-your-backup-history-in-sql-server.html
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return backup information for only specific databases. These are only the databases that currently exist on the server.
	
.PARAMETER Since
Datetime object used to narrow the results to a date
	
.PARAMETER Force
Returns a boatload of information, the way SQL Server returns it

.PARAMETER Last
Returns last full, diff and log backup sets

.PARAMETER LastFull
Returns last full backup set

.PARAMETER LastDiff
Returns last differential backup set

.PARAMETER LastLog
Returns last log backup set

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaBackupHistory

.EXAMPLE
Get-DbaBackupHistory -SqlServer sqlserver2014a

Returns server name, database, username, backup type, date for all backups databases on sqlserver2014a. This may return a ton of rows; consider using filters that are included in other examples.

.EXAMPLE
$cred = Get-Credential sqladmin
Get-DbaBackupHistory -SqlServer sqlserver2014a -SqlCredential $cred

Does the same as above but logs in as SQL user "sqladmin"

.EXAMPLE   
Get-DbaBackupHistory -SqlServer sqlserver2014a -Databases db1, db2 -Since '7/1/2016 10:47:00'

Returns backup information only for databases db1 and db2 on sqlserve2014a since July 1, 2016 at 10:47 AM.

.EXAMPLE   
Get-DbaBackupHistory -SqlServer sql2014 -Databases AdventureWorks2014, pubs -Force | Format-Table

Returns information only for AdventureWorks2014 and pubs, and makes the output pretty

.EXAMPLE   
Get-DbaBackupHistory -SqlServer sql2014 -Databases AdventureWorks2014 -Last

Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014
	
.EXAMPLE   
Get-DbaBackupHistory -SqlServer sql2014 -Databases AdventureWorks2014 -LastFull

Returns information about the most recent full backup for AdventureWorks2014 on sql2014	
	
.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2016 | Get-DbaBackupHistory

Returns database backup information for every database on every server listed in the Central Management Server on sql2016
	
.EXAMPLE   
Get-DbaBackupHistory -SqlServer sqlserver2014a, sql2016 -Force

Lots of detailed information for all databases on sqlserver2014a and sql2016.
	
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[Alias("SqlCredential")]
		[PsCredential]$Credential,
		[Parameter(ParameterSetName = "NoLast")]
		[switch]$Force,
		[Parameter(ParameterSetName = "NoLast")]
		[datetime]$Since,
		[Parameter(ParameterSetName = "Last")]
		[switch]$Last,
		[Parameter(ParameterSetName = "Last")]
		[switch]$LastFull,
		[Parameter(ParameterSetName = "Last")]
		[switch]$LastDiff,
		[Parameter(ParameterSetName = "Last")]
		[switch]$LastLog
	)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $Credential } }
	
	BEGIN
	{
		if ($Since -ne $null)
		{
			$Since = $Since.ToString("yyyy-MM-dd HH:mm:ss")
		}
	}
	
	PROCESS
	{
		$databases = $psboundparameters.Databases
		foreach ($server in $SqlServer)
		{
			try
			{
				Write-Verbose "Connecting to $server"
				$sourceserver = Connect-SqlServer -SqlServer $server -SqlCredential $Credential
				$servername = $sourceserver.name
				
				if ($sourceserver.VersionMajor -lt 9)
				{
					Write-Warning "SQL Server 2000 not supported"
					continue
				}
				$BackupSizeColumn = 'backup_size'
				if ($sourceserver.VersionMajor -ge 10)
				{
					# 2008 introduced compressed_backup_size
					$BackupSizeColumn = 'compressed_backup_size'
				}
				
				if ($last)
				{
					if ($databases -eq $null) { $databases = $sourceserver.databases.name }
					Get-DbaBackupHistory -SqlServer $sourceserver -LastFull -Databases $databases
					Get-DbaBackupHistory -SqlServer $sourceserver -LastDiff -Databases $databases
					Get-DbaBackupHistory -SqlServer $sourceserver -LastLog -Databases $databases
				}
				elseif ($LastFull -or $LastDiff -or $LastLog)
				{
					$sql = @()
					
					if ($databases -eq $null) { $databases = $sourceserver.databases.name }
					
					if ($LastFull) { $first = 'D'; $second = 'P' }
					if ($LastDiff) { $first = 'I'; $second = 'Q' }
					if ($LastLog) { $first = 'L'; $second = 'L' }
					
					$databases = $databases | Select-Object -Unique
					foreach ($database in $databases)
					{
						Write-Verbose "Processing $database"
						
						$sql += "SELECT
								  a.BackupSetRank,
								  a.Server,
								  a.[Database],
								  a.Username,
								  a.Start,
								  a.[End],
								  a.Duration,
								  a.[Path],
								  a.Type,
								  a.TotalSizeMB,
								  a.MediaSetId,
								  a.Software
								FROM (SELECT
								  RANK() OVER (ORDER BY backupset.media_set_id DESC) AS 'BackupSetRank',
								  '$servername' AS Server,
								  backupset.database_name AS [Database],
								  backupset.user_name AS Username,
								  backupset.backup_start_date AS Start,
								  backupset.backup_finish_date AS [End],
								  CAST(DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS varchar(4)) + ' ' + 'Seconds' AS Duration,
								  mediafamily.physical_device_name AS Path,
								  CAST(backupset.$BackupSizeColumn / 1048576 AS numeric(10, 2)) AS TotalSizeMB,
								  CASE backupset.type
									WHEN 'L' THEN 'Log'
									WHEN 'D' THEN 'Full'
									WHEN 'F' THEN 'File'
									WHEN 'I' THEN 'Differential'
									WHEN 'G' THEN 'Differential File'
									WHEN 'P' THEN 'Partial Full'
									WHEN 'Q' THEN 'Partial Differential'
									ELSE NULL
								  END AS Type,
								  backupset.media_set_id AS MediaSetId,
								  CASE mediafamily.device_type
									WHEN 2 THEN 'Disk'
									WHEN 102 THEN 'Permanent Disk  Device'
									WHEN 5 THEN 'Tape'
									WHEN 105 THEN 'Permanent Tape Device'
									WHEN 6 THEN 'Pipe'
									WHEN 106 THEN 'Permanent Pipe Device'
									WHEN 7 THEN 'Virtual Device'
									ELSE 'Unknown'
								  END AS DeviceType,
								  mediaset.software_name AS Software
								FROM msdb..backupmediafamily AS mediafamily
								INNER JOIN msdb..backupmediaset AS mediaset
								  ON mediafamily.media_set_id = mediaset.media_set_id
								INNER JOIN msdb..backupset AS backupset
								  ON backupset.media_set_id = mediaset.media_set_id
								WHERE backupset.database_name = '$database'
								AND (type = '$first'
								OR type = '$second')) AS a
								WHERE a.BackupSetRank = 1
								ORDER BY a.Type;"
					}
					
					$sql = $sql -join "; "
				}
				else
				{
					if ($Force -eq $true)
					{
						$select = "SELECT '$servername' AS [Server], * "
					}
					else
					{
						$select = "SELECT
									  '$servername' AS [Server],
									  backupset.database_name AS [Database],
									  backupset.user_name AS Username,
									  backupset.backup_start_date AS [Start],
									  backupset.backup_finish_date AS [End],
									  CAST(DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS varchar(4)) + ' ' + 'Seconds' AS Duration,
									  mediafamily.physical_device_name AS Path,
									  CAST((backupset.$BackupSizeColumn / 1048576) AS numeric(10, 2)) AS TotalSizeMB,
									  CASE backupset.type
										WHEN 'L' THEN 'Log'
										WHEN 'D' THEN 'Full'
										WHEN 'F' THEN 'File'
										WHEN 'I' THEN 'Differential'
										WHEN 'G' THEN 'Differential File'
										WHEN 'P' THEN 'Partial Full'
										WHEN 'Q' THEN 'Partial Differential'
										ELSE NULL
									  END AS Type,
									  backupset.media_set_id AS MediaSetId,
									  CASE mediafamily.device_type
										WHEN 2 THEN 'Disk'
										WHEN 102 THEN 'Permanent Disk  Device'
										WHEN 5 THEN 'Tape'
										WHEN 105 THEN 'Permanent Tape Device'
										WHEN 6 THEN 'Pipe'
										WHEN 106 THEN 'Permanent Pipe Device'
										WHEN 7 THEN 'Virtual Device'
										ELSE 'Unknown'
									  END AS DeviceType,
									  mediaset.software_name AS Software"
					}
					
					$from = " FROM msdb..backupmediafamily mediafamily
								 INNER JOIN msdb..backupmediaset mediaset ON mediafamily.media_set_id = mediaset.media_set_id
								 INNER JOIN msdb..backupset backupset ON backupset.media_set_id = mediaset.media_set_id"
					
					if ($databases -or $Since -or $Last -or $LastFull -or $LastLog -or $LastDiff)
					{
						$where = " WHERE "
					}
					
					$wherearray = @()
					
					if ($databases.length -gt 0)
					{
						$dblist = $databases -join "','"
						$wherearray += "database_name in ('$dblist')"
					}
					
					if ($Last -or $LastFull -or $LastLog -or $LastDiff)
					{
						$tempwhere = $wherearray -join " and "
						$wherearray += "type = 'Full' and mediaset.media_set_id = (select top 1 mediaset.media_set_id $from $tempwhere order by backupset.backup_finish_date DESC)"
					}
					
					if ($Since -ne $null)
					{
						$wherearray += "backupset.backup_finish_date >= '$since'"
					}
					
					if ($where.length -gt 0)
					{
						$wherearray = $wherearray -join " and "
						$where = "$where $wherearray"
					}
					
					$sql = "$select $from $where ORDER BY backupset.backup_finish_date DESC"
				}
				
				if (!$last)
				{
					Write-Debug $sql
					$results = $sourceserver.ConnectionContext.ExecuteWithResults($sql).Tables.Rows | Select-Object * -ExcludeProperty BackupSetRank, RowError, Rowstate, table, itemarray, haserrors
					$results = $results | Select-Object *, @{Name="FullName";Expression={$_.Path}}
					foreach ($result in $results)
					{ 
						$result | Select-DefaultView -ExcludeProperty FullName
					}				
                }
			}
			catch
			{
				Write-Warning $_
				Write-Exception $_
				continue
			}
		}
	}
}