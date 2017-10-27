#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Get-DbaBackupHistory {
	<#
	.SYNOPSIS
		Returns backup history details for databases on a SQL Server
	
	.DESCRIPTION
		Returns backup history details for some or all databases on a SQL Server.
		
		You can even get detailed information (including file path) for latest full, differential and log files.

		Backups taken with the CopyOnly option will NOT be returned, unless the IncludeCopyOnly switch is present
		
		Reference: http://www.sqlhub.com/2011/07/find-your-backup-history-in-sql-server.html
	
	.PARAMETER SqlInstance
		The SQL Server that you're connecting to.
	
	.PARAMETER SqlCredential
		Credential object used to connect to the SQL Server as a different user
	
	.PARAMETER Database
		The database(s) to process.
		If unspecified, all databases will be scanned for backup history.
	
	.PARAMETER ExcludeDatabase
		The database(s) to not process.
	
	.PARAMETER IncludeCopyOnly
		By default Get-DbaBackupHistory will ignore backups taken with the CopyOnly option. This switch will include them
	
	.PARAMETER Force
		Returns a boatload of information, the way SQL Server returns it
	
	.PARAMETER Since
		Datetime object used to narrow the results to a date
	
	.PARAMETER Last
		Returns last entire chain of full, diff and log backup sets - starting backwards from most recent log
	
	.PARAMETER LastFull
		Returns last full backup set
	
	.PARAMETER LastDiff
		Returns last differential backup set
	
	.PARAMETER LastLog
		Returns last log backup set
	
	.PARAMETER DeviceType
		Filters the backup set by this DeviceType. It takes well-known types ('Disk','Permanent Disk Device', 'Tape', 'Permanent Tape Device','Pipe','Permanent Pipe Device','Virtual Device') as well as custom integers (bring your own types)
	
	.PARAMETER Raw
		By default the command will group mediasets (striped backups across multiple files) into a single return object. If you'd prefer to have an object per backup file returned, use this switch
	
	.PARAMETER Type
		By default this command returns all types of backup together, unless one of the -Last* parameters is passed. Passing this allows to filter with this types
	
	.PARAMETER LastLsn
		Internal parameter: filter out backup history with last_lsn greater than this value (this helps speed up the retrieval process without resorting to process the full history)
	
	.PARAMETER EnableException
		By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
		This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
		Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
		
	.EXAMPLE
		Get-DbaBackupHistory -SqlInstance SqlInstance2014a
		
		Returns server name, database, username, backup type, date for all backups databases on SqlInstance2014a. This may return a ton of rows; consider using filters that are included in other examples.
	
	.EXAMPLE
		$cred = Get-Credential sqladmin
		Get-DbaBackupHistory -SqlInstance SqlInstance2014a -SqlCredential $cred
		
		Does the same as above but logs in as SQL user "sqladmin"
	
	.EXAMPLE
		Get-DbaBackupHistory -SqlInstance SqlInstance2014a -Database db1, db2 -Since '7/1/2016 10:47:00'
		
		Returns backup information only for databases db1 and db2 on SqlInstance2014a since July 1, 2016 at 10:47 AM.
	
	.EXAMPLE
		Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014, pubs -Force | Format-Table
		
		Returns information only for AdventureWorks2014 and pubs, and makes the output pretty
	
	.EXAMPLE
		Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last
		
		Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014
	
	.EXAMPLE
		Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType Disk
		
		Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, only for backups to disk
	
	.EXAMPLE
		Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType 148,107
		
		Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, only for backups with device_type 148 and 107
	
	.EXAMPLE
		Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -LastFull
		
		Returns information about the most recent full backup for AdventureWorks2014 on sql2014
	
	.EXAMPLE
		Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Type Full
		
		Returns information about all Full backups for AdventureWorks2014 on sql2014
	
	.EXAMPLE
		Get-DbaRegisteredServer -SqlInstance sql2016 | Get-DbaBackupHistory
		
		Returns database backup information for every database on every server listed in the Central Management Server on sql2016
	
	.EXAMPLE
		Get-DbaBackupHistory -SqlInstance SqlInstance2014a, sql2016 -Force
		
		Lots of detailed information for all databases on SqlInstance2014a and sql2016.
	
	.NOTES
		Tags: Storage, DisasterRecovery, Backup
		dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
		Copyright (C) 2016 Chrissy LeMaire
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0	
	
	.LINK
		https://dbatools.io/Get-DbaBackupHistory
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]
		$SqlInstance,
		
		[Alias("Credential")]
		[PsCredential]
		$SqlCredential,
		
		[Alias("Databases")]
		[object[]]
		$Database,
		
		[object[]]
		$ExcludeDatabase,
		
		[switch]
		$IncludeCopyOnly,
		
		[Parameter(ParameterSetName = "NoLast")]
		[switch]
		$Force,
		
		[Parameter(ParameterSetName = "NoLast")]
		[DateTime]
		$Since,
		
		[Parameter(ParameterSetName = "Last")]
		[switch]
		$Last,
		
		[Parameter(ParameterSetName = "Last")]
		[switch]
		$LastFull,
		
		[Parameter(ParameterSetName = "Last")]
		[switch]
		$LastDiff,
		
		[Parameter(ParameterSetName = "Last")]
		[switch]
		$LastLog,
		
		[string[]]
		$DeviceType,
		
		
		[switch]
		$Raw,
		
		[bigint]
		$LastLsn,
		
		[ValidateSet("Full", "Log", "Differential", "File", "Differential File", "Partial Full", "Partial Differential")]
		[string[]]$Type,
		
		[switch]
		[Alias('Silent')]$EnableException
	)
	
	begin {
		Write-Message -Level System -Message "Active Parameterset: $($PSCmdlet.ParameterSetName)"
		Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
		
		$IgnoreCopyOnly = $true
		If ($IncludeCopyOnly -eq $True) {
			$IgnoreCopyOnly = $false
		}

		$DeviceTypeMapping = @{
			'Disk' = 2
			'Permanent Disk Device' = 102
			'Tape' = 5
			'Permanent Tape Device' = 105
			'Pipe' = 6
			'Permanent Pipe Device' = 106
			'Virtual Device' = 7
		}
		$DeviceTypeFilter = @()
		foreach($DevType in $DeviceType) {
			if ($DevType -in $DeviceTypeMapping.Keys) {
				$DeviceTypeFilter += $DeviceTypeMapping[$DevType]
			} else {
				$DeviceTypeFilter += $DevType
			}
		}
		$BackupTypeMapping = @{
			'Log' = 'L'
			'Full' = 'D'
			'File' = 'F'
			'Differential' = 'I'
			'Differential File' = 'G'
			'Partial Full' = 'P'
			'Partial Differential' = 'Q'
		}
		$BackupTypeFilter = @()
		foreach($TypeFilter in $Type) {
			$BackupTypeFilter += $BackupTypeMapping[$TypeFilter]
		}
	
	}
	
	process {
		foreach ($instance in $SqlInstance) {
			
			try {
				Write-Message -Level VeryVerbose -Message "Connecting to $instance" -Target $instance
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failed to process Instance $Instance" -InnerErrorRecord $_ -Target $instance -Continue
			}
			
			if ($server.VersionMajor -lt 9) {
				Stop-Function -Message "SQL Server 2000 not supported" -Category LimitsExceeded -Target $instance -Continue
			}
			$backupSizeColumn = 'backup_size'
			if ($server.VersionMajor -ge 10) {
				# 2008 introduced compressed_backup_size
				$backupSizeColumn = 'compressed_backup_size'
			}
			
			$databases = @()
			if ($null -ne $Database) {
				ForEach ($db in $Database){
					$databases += [PScustomObject]@{name = $db}
				}
			}
			else {
				$databases = $server.Databases	
			}
			if ($ExcludeDatabase) {
				$databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
			}
			foreach($d in $DeviceTypeFilter) {
				$DeviceTypeFilterRight = "IN ('" + ($DeviceTypeFilter -Join "','") + "')"
			}
			
			foreach($b in $BackupTypeFilter) {
				$BackupTypeFilterRight = "IN ('" + ($BackupTypeFilter -Join "','") + "')"
			}

			if ($last) {
				
				foreach ($db in $databases) {
					
					#Get the full and build upwards
					$allbackups = @()
					$allbackups += $Fulldb = Get-DbaBackupHistory -SqlInstance $server -Database $db.Name -LastFull -raw:$Raw -DeviceType $DeviceType
					$DiffDB = Get-DbaBackupHistory -SqlInstance $server -Database $db.Name -LastDiff -raw:$Raw -DeviceType $DeviceType
					if ($DiffDb.LastLsn -gt $Fulldb.LastLsn -and  $DiffDb.DatabaseBackupLSN -eq $Fulldb.CheckPointLSN ) {
						Write-Message -Level Verbose -Message "Valid Differential backup "
						$Allbackups += $DiffDB
						$TLogStartLSN = ($diffdb.FirstLsn -as [bigint])
					}
					else {
						Write-Message -Level Verbose -Message "No Diff found"
						try { 
							[bigint]$TLogStartLSN = $Fulldb.FirstLsn 
						}
						catch {
							continue
						}
					}
					$Allbackups += $Logdb = Get-DbaBackupHistory -SqlInstance $server -Database $db.Name -raw:$raw -DeviceType $DeviceType -LastLsn $TLogstartLSN | Where-Object { 
						$_.Type -eq 'Log' -and [bigint]$_.LastLsn -gt [bigint]$TLogstartLSN -and [bigint]$_.DatabaseBackupLSN -eq [bigint]$Fulldb.CheckPointLSN -and $_.LastRecoveryForkGuid -eq $Fulldb.LastRecoveryForkGuid
					}
					#This line does the output for -Last!!!
					$Allbackups |  Sort-Object -Property LastLsn, Type
				
				}
				continue
			}
			
			if ($LastFull -or $LastDiff -or $LastLog) {
				#$sql = @()
				if ($LastFull) {
					$first = 'D'; $second = 'P'
				}
				if ($LastDiff) {
					$first = 'I'; $second = 'Q'
				}
				if ($LastLog) {
					$first = 'L'; $second = 'L'
				}
				$databases = $databases | Select-Object -Unique
				foreach ($db in $databases) {
					Write-Message -Level Verbose -Message "Processing $($db.name)" -Target $db
					$wherecopyonly = $null
					if ($IgnoreCopyOnly) { $wherecopyonly = "AND is_copy_only='0'" }
					if ($DeviceTypeFilter) {
						$DevTypeFilterWhere = "AND mediafamily.device_type $DeviceTypeFilterRight"
					}
					$sql += "
								SELECT
									a.BackupSetRank,
									a.Server,
									a.[Database],
									a.Username,
									a.Start,
									a.[End],
									a.Duration,
									a.[Path],
									a.Type,
									a.TotalSize,
									a.MediaSetId,
									a.BackupSetID,
									a.Software,
 									a.position,
 									a.first_lsn,
 									a.database_backup_lsn,
 									a.checkpoint_lsn,
 									a.last_lsn,
									a.first_lsn as 'FirstLSN',
 									a.database_backup_lsn as 'DatabaseBackupLsn',
 									a.checkpoint_lsn as 'CheckpointLsn',
 									a.last_lsn as 'Lastlsn',
 									a.software_major_version,
									a.DeviceType,
									a.is_copy_only,
									a.last_recovery_fork_guid
								FROM (SELECT
								  RANK() OVER (ORDER BY backupset.last_lsn DESC) AS 'BackupSetRank',
								  backupset.database_name AS [Database],
								  backupset.user_name AS Username,
								  backupset.backup_start_date AS Start,
								  backupset.server_name as [Server],
								  backupset.backup_finish_date AS [End],
								  DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS Duration,
								  mediafamily.physical_device_name AS Path,
								  backupset.$backupSizeColumn AS TotalSize,
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
								  backupset.backup_set_id as BackupSetID,
								  CASE mediafamily.device_type
									WHEN 2 THEN 'Disk'
									WHEN 102 THEN 'Permanent Disk Device'
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
								  mediaset.software_name AS Software,
								  backupset.is_copy_only,
								  backupset.last_recovery_fork_guid
								FROM msdb..backupmediafamily AS mediafamily
								JOIN msdb..backupmediaset AS mediaset
								  ON mediafamily.media_set_id = mediaset.media_set_id
								JOIN msdb..backupset AS backupset
								  ON backupset.media_set_id = mediaset.media_set_id
								WHERE backupset.database_name = '$($db.Name)' $wherecopyonly
								AND (type = '$first' OR type = '$second')
								$DevTypeFilterWhere
								) AS a
								WHERE a.BackupSetRank = 1
								ORDER BY a.Type;
								"
				}
				$sql = $sql -join "; "
			}
			else {
				if ($Force -eq $true) {
					$select = "SELECT * "
				}
				else {
					$select = "
							SELECT
							  backupset.database_name AS [Database],
							  backupset.user_name AS Username,
							  backupset.server_name as [server],
							  backupset.backup_start_date AS [Start],
							  backupset.backup_finish_date AS [End],
							  DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS Duration,
							  mediafamily.physical_device_name AS Path,
							  backupset.$backupSizeColumn AS TotalSize,
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
								WHEN 102 THEN 'Permanent Disk Device'
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
							  backupset.first_lsn as 'FirstLSN',
							  backupset.database_backup_lsn as 'DatabaseBackupLsn',
							  backupset.checkpoint_lsn as 'CheckpointLsn',
							  backupset.last_lsn as 'Lastlsn',
							  backupset.software_major_version,
							  mediaset.software_name AS Software,
							  backupset.is_copy_only,
							  backupset.last_recovery_fork_guid"
				}
				
				$from = " FROM msdb..backupmediafamily mediafamily
							 INNER JOIN msdb..backupmediaset mediaset ON mediafamily.media_set_id = mediaset.media_set_id
							 INNER JOIN msdb..backupset backupset ON backupset.media_set_id = mediaset.media_set_id"
				if ($Database -or $Since -or $Last -or $LastFull -or $LastLog -or $LastDiff -or $IgnoreCopyOnly -or $DeviceTypeFilter -or $LastLsn -or $BackupTypeFilter) {
					$where = " WHERE "
				}
				
				$wherearray = @()
				
				if ($Database.length -gt 0) {
					$dblist = $Database -join "','"
					$wherearray += "database_name IN ('$dblist')"
				}
				
				if ($Last -or $LastFull -or $LastLog -or $LastDiff) {
					$tempwhere = $wherearray -join " AND "
					$wherearray += "type = 'Full' AND mediaset.media_set_id = (select top 1 mediaset.media_set_id $from $tempwhere order by backupset.last_lsn DESC)"
				}
				
				if ($Since -ne $null) {
					$wherearray += "backupset.backup_finish_date >= '$($Since.ToString("yyyy-MM-ddTHH:mm:ss"))'"
				}
				
				if ($IgnoreCopyOnly -eq $true) {
					$wherearray += "is_copy_only='0'"
				}
				if ($DeviceTypeFilter) {
					$wherearray += "mediafamily.device_type $DeviceTypeFilterRight"
				}
				if ($BackupTypeFilter) {
					$wherearray += "backupset.type $BackupTypeFilterRight"
				}
				
				if ($LastLsn) {
					$wherearray += "backupset.last_lsn > $LastLsn"
				}
				if ($where.length -gt 0) {
					$wherearray = $wherearray -join " AND "
					$where = "$where $wherearray"
				}
				
				$sql = "$select $from $where ORDER BY backupset.last_lsn DESC"
			}

			Write-Message -Level Debug -Message $sql
			Write-Message -Level SomewhatVerbose -Message "Executing sql query"
			$results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows | Select-Object * -ExcludeProperty BackupSetRank, RowError, Rowstate, table, itemarray, haserrors
			
			if ($raw) {
				Write-Message -Level SomewhatVerbose -Message "Processing as Raw Output"
				$results | Select-Object *, @{ Name = "FullName"; Expression = { $_.Path } }
				Write-Message -Level SomewhatVerbose -Message "$($results.Count) result sets found"
			}
			else {
				Write-Message -Level SomewhatVerbose -Message "Processing as Grouped output"
				$GroupedResults = $results | Group-Object -Property backupsetid
				Write-Message -Level SomewhatVerbose -Message "$($GroupedResults.Count) result-groups found"
				$groupResults = @()
				foreach ($group in $GroupedResults) {
					
					$fileSql = "select file_type as FileType, logical_name as LogicalName, physical_name as PhysicalName
								from msdb.dbo.backupfile where backup_set_id='$($Group.group[0].BackupSetID)'"
					
					Write-Message -Level Debug -Message "FileSQL: $fileSql"
	
					$historyObject = New-Object Sqlcollaborative.Dbatools.Database.BackupHistory
					$historyObject.ComputerName = $server.NetName
					$historyObject.InstanceName = $server.ServiceName
					$historyObject.SqlInstance = $server.DomainInstanceName
					$historyObject.Database = $group.Group[0].Database
					$historyObject.UserName = $group.Group[0].UserName
					$historyObject.Start = ($group.Group.Start | Measure-Object -Minimum).Minimum
					$historyObject.End = ($group.Group.End | Measure-Object -Maximum).Maximum
					$historyObject.Duration = New-TimeSpan -Seconds ($group.Group.Duration | Measure-Object -Maximum).Maximum
					$historyObject.Path = $group.Group.Path
					$historyObject.TotalSize = ($group.Group.TotalSize | Measure-Object -Sum).Sum
					$historyObject.Type = $group.Group[0].Type
					$historyObject.BackupSetId = $group.Group[0].BackupSetId
					$historyObject.DeviceType = $group.Group[0].DeviceType
					$historyObject.Software = $group.Group[0].Software
					$historyObject.FullName = $group.Group.Path
					$historyObject.FileList = $server.ConnectionContext.ExecuteWithResults($fileSql).Tables.Rows
					$historyObject.Position = $group.Group[0].Position
					$historyObject.FirstLsn = $group.Group[0].First_LSN
					$historyObject.DatabaseBackupLsn = $group.Group[0].database_backup_lsn
					$historyObject.CheckpointLsn = $group.Group[0].checkpoint_lsn
					$historyObject.LastLsn = $group.Group[0].Last_Lsn
					$historyObject.SoftwareVersionMajor = $group.Group[0].Software_Major_Version
					$historyObject.IsCopyOnly = if($group.Group[0].is_copy_only -eq 1){$true}else{$false}
					$HistoryObject.LastRecoveryForkGuid = $group.Group[0].last_recovery_fork_guid
					$groupResults += $historyObject
				}
				$groupResults | Sort-Object -Property LastLsn, Type
			}
		}
	}
}
