Function Get-DbaRestoreHistory
{
<#
.SYNOPSIS
Returns restore history details for databases on a SQL Server
	
.DESCRIPTION
By default, this command will return the server name, database, username, restore type, date, from file and to files.

Thanks to https://www.mssqltips.com/sqlservertip/1724/when-was-the-last-time-your-sql-server-database-was-restored/ for the query and https://sqlstudies.com/2016/07/27/when-was-this-database-restored/ for the idea.
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return restore information for only specific databases. These are only the databases that currently exist on the server.
	
.PARAMETER Exclude
Return restore information for all but these specific databases

.PARAMETER Since
Datetime object used to narrow the results to a date
	
.PARAMETER Detailed
Returns default information plus From (\\server\backups\test.bak) and To (the mdf and ldf locations) information
	
.PARAMETER Force
Returns a ton of information about the backup history with no max rows

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaRestoreHistory

.EXAMPLE
Get-DbaRestoreHistory -SqlServer sqlserver2014a

Returns server name, database, username, restore type, date for all restored databases on sqlserver2014a.

.EXAMPLE   
Get-DbaRestoreHistory -SqlServer sqlserver2014a -Databases db1, db2 -Since '7/1/2016 10:47:00'

Returns restore information only for databases db1 and db2 on sqlserve2014a since July 1, 2016 at 10:47 AM.
	
.EXAMPLE   
Get-DbaRestoreHistory -SqlServer sqlserver2014a, sql2016 -Detailed -Exclude db1

Lots of detailed information for all databases except db1 on sqlserver2014a and sql2016

.EXAMPLE   
Get-DbaRestoreHistory -SqlServer sql2014 -Databases AdventureWorks2014, pubs -Detailed | Format-Table

Adds From and To file information to output, returns information only for AdventureWorks2014 and pubs, and makes the output pretty

.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2016 | Get-DbaRestoreHistory

Returns database restore information for every database on every server listed in the Central Management Server on sql2016
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[Alias("SqlCredential")]
		[PsCredential]$Credential,
		[datetime]$Since,
		[switch]$Detailed,
		[switch]$Force
	)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $Credential } }
	
	BEGIN
	{
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		
		$collection = New-Object System.Collections.ArrayList
		
		if ($Since -ne $null)
		{
			$Since = $Since.ToString("yyyy-MM-dd HH:mm:ss")
		}
	}
	
	PROCESS
	{
		foreach ($server in $SqlServer)
		{
			try
			{
				$sourceserver = Connect-SqlServer -SqlServer $server -SqlCredential $Credential
				
				if ($force -eq $true)
				{
					$select = "SELECT * "
				}
				else
				{
					$select = "SELECT 
				     '$server' AS [Server],
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
								 FOR XML PATH('')), 1, 2, ''), '') AS [To]  
				  "
				}
				
				$from = " FROM msdb.dbo.restorehistory rsh
					INNER JOIN msdb.dbo.backupset bs ON rsh.backup_set_id = bs.backup_set_id"
				
				if ($exclude.length -gt 0 -or $databases.length -gt 0 -or $Since.length -gt 0)
				{
					$where = " WHERE "
				}
				
				$wherearray = @()
				
				if ($exclude.length -gt 0)
				{
					$dblist = $exclude -join "','"
					$wherearray += " destination_database_name not in ('$dblist')"
				}
				
				if ($databases.length -gt 0)
				{
					$dblist = $databases -join "','"
					$wherearray += "destination_database_name in ('$dblist')"
				}
				
				if ($Since -ne $null)
				{
					$wherearray += "rsh.restore_date >= '$since'"
				}
				
				if ($where.length -gt 0)
				{
					$wherearray = $wherearray -join " and "
					$where = "$where $wherearray"
				}
				
				$sql = "$select $from $where"
				Write-Debug $sql
				$results = $sourceserver.ConnectionContext.ExecuteWithResults($sql).Tables
			}
			catch
			{
				Write-Warning "$_ `nMoving on"
				continue
			}
			
			$null = $collection.Add($results)
		}
	}
	
	END
	{
		if ($Detailed -eq $true -or $Force -eq $true)
		{
			return $collection.rows
		}
		
		return ($collection.rows | Select-Object * -ExcludeProperty From, To, RowError, Rowstate, table, itemarray, haserrors)
	}
}