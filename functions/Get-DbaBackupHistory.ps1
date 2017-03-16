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

.PARAMETER IgnoreCopyOnly
If set, Get-DbaBackupHistory will ignore CopyOnly backups

.PARAMETER Raw
By default the command will group mediasets (striped backups across multiple files) into a single return object. If you'd prefer to have an object per backp file returned, use this switch

.NOTES
Tags: Storage, DisasterRecovery, Backup
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
		[switch]$IgnoreCopyOnly,
		[Parameter(ParameterSetName = "NoLast")]
		[switch]$Force,
		[datetime]$Since = '01/01/01 00:00:00',
		[Parameter(ParameterSetName = "Last")]
		[switch]$Last,
		[Parameter(ParameterSetName = "Last")]
		[switch]$LastFull,
		[Parameter(ParameterSetName = "Last")]
		[switch]$LastDiff,
		[Parameter(ParameterSetName = "Last")]
		[switch]$LastLog,
		[switch]$raw
	)

	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $Credential } }
	
	BEGIN
	{
		$FunctionName = $FunctionName = (Get-PSCallstack)[0].Command
		if ($Since -ne $null)
		{
			$Since = $Since.ToString("yyyy-MM-dd HH:mm:ss")
		}
	}
	
	PROCESS
	{
		$databases = $psboundparameters.Databases
		foreach ($instance in $SqlServer)
		{
			try
			{
				Write-Verbose "$FunctionName - Connecting to $instance"
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $Credential
				
				if ($server.VersionMajor -lt 9 -and $IgnoreCopyOnly)
				{
					Write-Warning "$FunctionName - IgnoreCopyOnly not supported on SQL Server 2000"
					Continue
					$IgnoreCopyOnly = $false
				}
				#$BackupSizeColumn = 'backup_size'
				$BackupSizeColumn = "CAST(backupset.backup_size / 1048576 AS numeric(10, 2)) AS TotalSizeMB"
				if ($server.VersionMajor -ge 10)
				{
					# 2008 introduced compressed_backup_size
					#$BackupSizeColumn = 'compressed_backup_size'
					$BackupSizeColumn += ",backupset.compressed_backup_size"
				}
				
				if ($last)
				{
					if ($databases -eq $null) { $databases = $server.databases.name }
					
					foreach ($db in $databases)
					{
						Get-DbaBackupHistory -SqlServer $server -LastFull -Databases $db -raw:$raw -Since $Since
						Get-DbaBackupHistory -SqlServer $server -LastDiff -Databases $db -raw:$raw -Since $Since
						Get-DbaBackupHistory -SqlServer $server -LastLog -Databases $db -raw:$raw -Since $Since
					}
				}
				elseif ($LastFull -or $LastDiff -or $LastLog)
				{
					
					if ($databases -eq $null) { $databases = $server.databases.name }
					
					if ($LastFull) { $first = 'D'; $second = 'P' }
					if ($LastDiff) { $first = 'I'; $second = 'Q' }
					if ($LastLog) { $first = 'L'; $second = 'L' }
					
					$databases = $databases | Select-Object -Unique

					$database = $databases -join ''','''
					Write-Verbose "$FunctionName - Processing $database"
					
					$InnerFilter = " AND (type = '$first' OR type = '$second')"
					if ($IgnoreCopyOnly)
					{
						$InnerFilter += " AND is_copy_only='0' "
					}
					if ($Since -ne $null)
					{
						$InnerFilter += " AND backup_finish_date >= '$since'"
					}
					$InnerFilter += " AND database_name in ('$database')"
					$innersql = "
					SELECT MAX(backup_start_date) AS backup_start_date, database_name
					FROM msdb..backupset
					WHERE 1=1
					$InnerFilter
					GROUP BY database_name
					"
					$sql += "SELECT
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
								a.Software,
								a.backupsetid,
								a.position,
								a.first_lsn,
								a.database_backup_lsn,
								a.checkpoint_lsn,
								a.last_lsn,
								a.software_major_version
							FROM (SELECT
								backupset.database_name AS [Database],
								backupset.user_name AS Username,
								backupset.backup_start_date AS Start,
								backupset.server_name as [server],
								backupset.backup_finish_date AS [End],"
							if ($IgnoreCopyOnly)
							{
								$sql+= "backupset.is_copy_only,"
							}	
							$sql+=	"CAST(DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS varchar(4)) + ' ' + 'Seconds' AS Duration,
								mediafamily.physical_device_name AS Path,
								$BackupSizeColumn,
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
								mediafamily.media_family_id as mediafamilyid,
								backupset.backup_set_id as backupsetid,
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
								backupset.position,
								backupset.first_lsn,
								backupset.database_backup_lsn,
								backupset.checkpoint_lsn,
								backupset.last_lsn,
								backupset.software_major_version,
								mediaset.software_name AS Software
							FROM msdb..backupmediafamily AS mediafamily
							INNER JOIN msdb..backupmediaset AS mediaset
								ON mediafamily.media_set_id = mediaset.media_set_id
							INNER JOIN msdb..backupset AS backupset
								ON backupset.media_set_id = mediaset.media_set_id
							INNER JOIN ($innersql) LegacyRank
							ON LegacyRank.database_name = backupset.database_name
							AND LegacyRank.backup_start_date = backupset.backup_start_date
							WHERE backupset.database_name in ('$database')"
						if ($IgnoreCopyOnly)
						{
							$sql += " AND is_copy_only='0' "
						}
						if ($Since -ne $null)
						{
							$sql += " AND backupset.backup_finish_date >= '$since'"
						}
						$sql+= " AND (type = '$first'
							OR type = '$second')) AS a
							ORDER BY a.Type;"
						
				}
				else
				{
					if ($Force -eq $true)
					{
						$select = "SELECT * "
					}
					else
					{
						$select = "SELECT
									  backupset.database_name AS [Database],
									  backupset.user_name AS Username,
									  backupset.server_name as [server],
									  backupset.backup_start_date AS [Start],
									  backupset.backup_finish_date AS [End],
									  CAST(DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS varchar(4)) + ' ' + 'Seconds' AS Duration,
									  mediafamily.physical_device_name AS Path,
									 $BackupSizeColumn,
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
									  mediafamily.media_family_id as mediafamilyid,
		   							  backupset.backup_set_id as backupsetid,
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
									  backupset.position,
									  backupset.first_lsn,
									  backupset.database_backup_lsn,
									  backupset.checkpoint_lsn,
									  backupset.last_lsn,
		   							  backupset.software_major_version,
									  mediaset.software_name AS Software"
					}
					
					$from = " FROM msdb..backupmediafamily mediafamily
								 INNER JOIN msdb..backupmediaset mediaset ON mediafamily.media_set_id = mediaset.media_set_id
								 INNER JOIN msdb..backupset backupset ON backupset.media_set_id = mediaset.media_set_id"
					
					if ($databases -or $Since -or $Last -or $LastFull -or $LastLog -or $LastDiff -or $IgnoreCopyOnly)
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
					
					if ($IgnoreCopyOnly)
					{
						$wherearray += "is_copy_only='0'"
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
					$results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows | Select-Object * -ExcludeProperty RowError, Rowstate, table, itemarray, haserrors

					if ($raw)
					{
						write-verbose "$FunctionName - Raw Ouput"
						$results = $results | Select-Object *, @{ Name = "FullName"; Expression = { $_.Path } }
					}
					else
					{
						write-verbose "$FunctionName - Grouped output"
						$GroupedResults = $results | Group-Object -Property backupsetid
						$GroupResults = @()
						foreach ($group in $GroupedResults)
						{
							
							$FileSql = "select
										file_type as FileType,
										logical_name as LogicalName,
										physical_name as PhysicalName
										from msdb.dbo.backupfile
										where backup_set_id='$($Group.group[0].BackupSetID)'"
							write-Debug "$FunctionName = FileSQL: $FileSql"
							$GroupResults += [PSCustomObject]@{
								ComputerName = $server.NetName
								InstanceName = $server.ServiceName
								SqlInstance = $server.DomainInstanceName
								Database = $group.Group[0].Database
								UserName = $group.Group[0].UserName
								Start = ($group.Group.Start | measure-object -Minimum).Minimum
								End = ($group.Group.End | measure-object -Maximum).Maximum
								Duration = ($group.Group.Duration | measure-object -Maximum).Maximum
								Path = $group.Group.Path
								TotalSizeMb = ($group.group.TotalSizeMb | measure-object -Sum).sum
								BackupSizeMb = ($group.group.TotalSizeMb | measure-object -Sum).sum
								BackupSize = (($group.group.TotalSizeMb | measure-object -Sum).sum)*8*1024
								CompressedBackupSize = ($group.group.compressed_backup_size | measure-object -Sum).sum
								CompressedBackupSizeMb = ($group.group.compressed_backup_size | measure-object -Sum).sum / 1mb
								Type = $group.Group[0].Type
								BackupSetupId = $group.Group[0].BackupSetId
								DeviceType = $group.Group[0].DeviceType
								Software = $group.Group[0].Software
								FullName = $group.Group.Path
								FileList = $server.ConnectionContext.ExecuteWithResults($Filesql).Tables.Rows
								Position = $group.Group[0].Position
								FirstLsn = $group.Group[0].First_LSN
								DatabaseBackupLsn = $group.Group[0].database_backup_lsn
								CheckpointLsn = $group.Group[0].checkpoint_lsn
								LastLsn = $group.Group[0].Last_Lsn
								SoftwareVersionMajor = $group.Group[0].Software_Major_Version
							}
							
						}
						$results = $GroupResults | Sort-Object -Property End -Descending
					}
					foreach ($result in $results)
					{
						$result | Select-DefaultView -ExcludeProperty FullName, Filelist, Position, FirstLsn, DatabaseBackupLSN, CheckPointLsn, LastLsn, SoftwareVersionMajor, CompressedBackupSize, CompressedBackupSizeMb, BackupSize
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