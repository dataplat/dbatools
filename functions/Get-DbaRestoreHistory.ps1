Function Get-DbaRestoreHistory
{
<#
.SYNOPSIS
Returns restore history details for databases on a SQL Server
	
.DESCRIPTION
By default, this command will return the server name, database, username, restore type, date, from file and to files.

Thanks to https://www.mssqltips.com/SqlInstancetip/1724/when-was-the-last-time-your-sql-server-database-was-restored/ for the query and https://sqlstudies.com/2016/07/27/when-was-this-database-restored/ for the idea.
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Database
The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is autopopulated from the server

.PARAMETER Since
Datetime object used to narrow the results to a date
	
.PARAMETER Force
Returns a ton of information about the backup history with no max rows

.PARAMETER Last
Returns the last restore action performed on each specified database

.NOTES
Tags: DisasterRecovery, Backup, Restore, Databases

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaRestoreHistory

.EXAMPLE
Get-DbaRestoreHistory -SqlInstance sql2016

Returns server name, database, username, restore type, date for all restored databases on sql2016.

.EXAMPLE   
Get-DbaRestoreHistory -SqlInstance sql2016 -Database db1, db2 -Since '7/1/2016 10:47:00'

Returns restore information only for databases db1 and db2 on sqlserve2014a since July 1, 2016 at 10:47 AM.
	
.EXAMPLE   
Get-DbaRestoreHistory -SqlInstance sql2016, sql2016 -Exclude db1

Lots of detailed information for all databases except db1 on sql2016 and sql2016

.EXAMPLE   
Get-DbaRestoreHistory -SqlInstance sql2014 -Database AdventureWorks2014, pubs | Format-Table

Adds From and To file information to output, returns information only for AdventureWorks2014 and pubs, and makes the output pretty

.EXAMPLE   
Get-SqlRegisteredServerName -SqlInstance sql2016 | Get-DbaRestoreHistory

Returns database restore information for every database on every server listed in the Central Management Server on sql2016
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[datetime]$Since,
		[switch]$Force,
		[switch]$Last
	)
	
	begin
	{		
		if ($Since -ne $null)
		{
			$Since = $Since.ToString("yyyy-MM-dd HH:mm:ss")
		}
	}
	
	process
	{
		foreach ($instance in $SqlInstance)
		{
			try
			{
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
				
				if ($server.VersionMajor -lt 9)
				{
					Write-Warning "SQL Server 2000 not supported"
					continue
				}
				
				$computername = $server.NetName
				$instancename = $server.ServiceName
				$servername = $server.DomainInstanceName
				
				if ($force -eq $true)
				{
					$select = "SELECT '$computername' AS [ComputerName],
					'$instancename' AS [InstanceName],
					'$servername' AS [SqlInstance], * "
				}
				else
				{
					$select = "SELECT 
					'$computername' AS [ComputerName],
					'$instancename' AS [InstanceName],
					'$servername' AS [SqlInstance],
					 rsh.destination_database_name AS [Database],
					 --rsh.restore_history_id as RestoreHistoryID,
					 rsh.user_name AS [Username],
					 CASE 
						 WHEN rsh.restore_type = 'D' THEN 'Database'
						 WHEN rsh.restore_type = 'F' THEN 'File'
						 WHEN rsh.restore_type = 'G' THEN 'Filegroup'
						 WHEN rsh.restore_type = 'I' THEN 'Differential'
						 WHEN rsh.restore_type = 'L' THEN 'Log'
						 WHEN rsh.restore_type = 'V' THEN 'Verifyonly'
						 WHEN rsh.restore_type = 'R' THEN 'Revert'
						 ELSE rsh.restore_type
					 END AS [RestoreType],
					 rsh.restore_date AS [Date],
					 ISNULL(STUFF((SELECT ', ' + bmf.physical_device_name 
									FROM msdb.dbo.backupmediafamily bmf
								   WHERE bmf.media_set_id = bs.media_set_id
								 FOR XML PATH('')), 1, 2, ''), '') AS [From],
					 ISNULL(STUFF((SELECT ', ' + rf.destination_phys_name 
									FROM msdb.dbo.restorefile rf
								   WHERE rsh.restore_history_id = rf.restore_history_id
								 FOR XML PATH('')), 1, 2, ''), '') AS [To],
					bs.first_lsn,
					bs.last_lsn,
					bs.checkpoint_lsn,
					bs.database_backup_lsn
				  "
				}
				
				$from = " FROM msdb.dbo.restorehistory rsh
					INNER JOIN msdb.dbo.backupset bs ON rsh.backup_set_id = bs.backup_set_id"
				
				if ($ExcludeDatabase -or $Database -or $Since -or $last)
				{
					$where = " WHERE "
				}
				
				$wherearray = @()
				
				if ($ExcludeDatabase)
				{
					$dblist = $ExcludeDatabase -join "','"
					$wherearray += " destination_database_name not in ('$dblist')"
				}
				
				if ($Database)
				{
					$dblist = $Database -join "','"
					$wherearray += "destination_database_name in ('$dblist')"
				}
				
				if ($Since -ne $null)
				{
					$wherearray += "rsh.restore_date >= '$since'"
				}
				

				if ($last)
				{
					$wherearray += "rsh.backup_set_id in
						(select max(backup_set_id) from msdb.dbo.restorehistory
						group by destination_database_name
						)"
				}

				if ($where.length -gt 0)
				{
					$wherearray = $wherearray -join " and "
					$where = "$where $wherearray"
				}
				
				$sql = "$select $from $where"
				
				Write-Debug $sql
				
				$results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows 

				if ($last)
				{
					$ga = $results | group-Object database
					$tmpres = @()	
					$ga | foreach-Object {
						$tmpres += $_.Group | SORT-OBJECT RESTORE_DATE -Descending | SELECT * -first 1 
					}
					$results = $tmpres
				}
				$results | Select-DefaultView -Exclude first_lsn,last_lsn,checkpoint_lsn,database_backup_lsn,RowError,RowState,Table,ItemArray,HasErrors
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

