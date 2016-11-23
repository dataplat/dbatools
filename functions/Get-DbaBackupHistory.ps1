Function Get-DbaBackupHistory
{
<#
.SYNOPSIS
Returns backup history details for databases on a SQL Server
	
.DESCRIPTION
By default, this command will XYZ

Thanks to http://www.sqlhub.com/2011/07/find-your-backup-history-in-sql-server.html
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return backup information for only specific databases. These are only the databases that currently exist on the server.
	
.PARAMETER Exclude
Return backup information for all but these specific databases

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
https://dbatools.io/Get-DbaBackupHistory

.EXAMPLE
Get-DbaBackupHistory -SqlServer sqlserver2014a

Returns server name, database, username, backup type, date for all backupd databases on sqlserver2014a.

.EXAMPLE   
Get-DbaBackupHistory -SqlServer sqlserver2014a -Databases db1, db2 -Since '7/1/2016 10:47:00'

Returns backup information only for databases db1 and db2 on sqlserve2014a since July 1, 2016 at 10:47 AM.
	
.EXAMPLE   
Get-DbaBackupHistory -SqlServer sqlserver2014a, sql2016 -Detailed -Exclude db1

Lots of detailed information for all databases except db1 on sqlserver2014a and sql2016

.EXAMPLE   
Get-DbaBackupHistory -SqlServer sql2014 -Databases AdventureWorks2014, pubs -Detailed | Format-Table

Adds From and To file information to output, returns information only for AdventureWorks2014 and pubs, and makes the output pretty

.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2016 | Get-DbaBackupHistory

Returns database backup information for every database on every server listed in the Central Management Server on sql2016
	
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
					$select = "SELECT '$server' AS [Server], * "
				}
				else
				{
					# needs compressedbackup_size for systems that support it
					$select = "SELECT 
					   '$server' AS [Server],
					    backupset.Database_Name As [Database],
						backupset.User_Name AS Username,
					    backupset.Backup_Start_Date as [Start],
					    backupset.Backup_Finish_Date as [End],
						CAST(DATEDIFF(second, backupset.backup_start_date, backupset.backup_finish_date) AS VARCHAR(4)) + ' ' + 'Seconds' as Duration,
					    mediafamily.Physical_Device_Name AS Path,
					    CASE backupset.Type      
				            WHEN 'L' THEN 'Log'
				            WHEN 'D' THEN 'Full'
				            WHEN 'F' THEN 'File'
				            WHEN 'I' THEN 'Differential'
				            WHEN 'G' THEN 'DifferentialFile'
				            WHEN 'P' THEN 'PartialFull'
				            WHEN 'Q' THEN 'PartialDiff'
				        ELSE NULL END AS Type,
				    CAST((backupset.Backup_Size/1048576) AS NUMERIC(10,2)) AS BackupSizeInMB,
					backupset.Media_Set_ID as MediaSetId, mediaset.Software_Name AS Software"
				}
				
				$from = " FROM msdb..BackupMediaFamily mediafamily INNER JOIN msdb..BackupMediaSet mediaset
						ON mediafamily.Media_Set_ID = mediaset.Media_Set_ID INNER JOIN msdb..BackupSet backupset
						ON backupset.Media_Set_ID = mediaset.Media_Set_ID"
				
				if ($exclude.length -gt 0 -or $databases.length -gt 0 -or $Since.length -gt 0)
				{
					$where = " WHERE "
				}
				
				$wherearray = @()
				
				if ($exclude.length -gt 0)
				{
					$dblist = $exclude -join "','"
					$wherearray += " database_name not in ('$dblist')"
				}
				
				if ($databases.length -gt 0)
				{
					$dblist = $databases -join "','"
					$wherearray += "database_name in ('$dblist')"
				}
				
				if ($Since -ne $null)
				{
					$wherearray += "BackupStartDate >= '$since'"
				}
				
				if ($where.length -gt 0)
				{
					$wherearray = $wherearray -join " and "
					$where = "$where $wherearray"
				}
				
				$sql = "$select $from $where ORDER BY backupset.Backup_Finish_Date DESC"
				Write-Debug $sql
				$results = $sourceserver.ConnectionContext.ExecuteWithResults($sql).Tables
			}
			catch
			{
				Write-Exception $_
				Write-Warning "$_ `nMoving on"
				continue
			}
			
			if ($Detailed -eq $true -or $Force -eq $true)
			{
				$results.rows
				continue
			}
			
			($results.rows | Select-Object * -ExcludeProperty From, To, RowError, Rowstate, table, itemarray, haserrors)
		}
	}
}