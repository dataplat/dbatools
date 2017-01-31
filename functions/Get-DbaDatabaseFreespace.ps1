function Get-DbaDatabaseFreespace
{
<#
.SYNOPSIS
Returns database file space information for database files on a SQL instance.

.DESCRIPTION
This function returns database file space information for a SQL Instance or group of SQL 
Instances. Information is based on a query against sys.database_files and the FILEPROPERTY
function to query and return information. The function can accept a single instance or
multiple instances. By default, only user dbs will be shown, but using the IncludeSystemDBs
switch will include system databases

.NOTES 
Original Author: Michael Fal (@Mike_Fal), http://mikefal.net

File free space script borrowed and modified from Glenn Berry's DMV scripts (http://www.sqlskills.com/blogs/glenn/category/dmv-queries/)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, currend Windows login will be used.

.PARAMETER IncludeSystemDBs
Switch parameter that when used will display system database information
	
.PARAMETER Databases
Specify one or more databases to process. 

.PARAMETER Exclude
Specify one or more databases to exclude.
	
.LINK
https://dbatools.io/Get-DbaDatabaseFreespace

.EXAMPLE
Get-DbaDatabaseFreespace -SqlServer localhost

Returns all user database files and free space information for the local host

.EXAMPLE
Get-DbaDatabaseFreespace -SqlServer localhost | Where-Object {$_.PercentUsed -gt 80}

Returns all user database files and free space information for the local host. Filters
the output object by any files that have a percent used of greater than 80%.

.EXAMPLE
@('localhost','localhost\namedinstance') | Get-DbaDatabaseFreespace

Returns all user database files and free space information for the localhost and
localhost\namedinstance SQL Server instances. Processes data via the pipeline.

.EXAMPLE
Get-DbaDatabaseFreespace -SqlServer localhost -Databases db1, db2

Returns database files and free space information for the db1 and db2 on localhost. 
#>
	[CmdletBinding()]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$IncludeSystemDBs)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{
		$sql = "SELECT 
				    @@SERVERNAME as SqlServer
				    ,DB_NAME() as DBName
				    ,f.name AS [FileName]
				    ,fg.name AS [Filegroup] 
				    ,f.physical_name AS [PhysicalName]
				    ,CAST(CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS DECIMAL(15,2)) as [UsedSpaceMB]
				    ,CAST(f.size/128.0 - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS DECIMAL(15,2)) AS [FreeSpaceMB]
				    ,CAST((f.size/128.0) AS DECIMAL(15,2)) AS [FileSizeMB]
				    ,CAST((FILEPROPERTY(f.name, 'SpaceUsed')/(f.size/1.0)) * 100 as DECIMAL(15,2)) as [PercentUsed]
				FROM sys.database_files AS f WITH (NOLOCK) 
				LEFT OUTER JOIN sys.filegroups AS fg WITH (NOLOCK)
				ON f.data_space_id = fg.data_space_id"
		
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
	}
	
	PROCESS
	{
		foreach ($instance in $SqlServer)
		{
			#For each SQL Server in collection, connect and get SMO object
			Write-Verbose "Connecting to $instance"
			$server = Connect-SqlServer $instance -SqlCredential $SqlCredential
			
			# If IncludeSystemDBs is true, include systemdbs
			# only look at online databases (Status equal normal)
			
			if ($server.VersionMajor -eq 8)
			{
				Write-Warning "SQL Server 2000 is not supported. Skipping $server"
				continue
			}
			
			try
			{
				if ($databases.length -gt 0)
				{
					$dbs = $server.Databases | Where-Object { $databases -contains $_.Name }
				}
				elseif ($IncludeSystemDBs)
				{
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' }
				}
				else
				{
					$dbs = $server.Databases | Where-Object { $_.status -eq 'Normal' -and $_.IsSystemObject -eq 0 }
				}
				
				if ($exclude.length -gt 0)
				{
					$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
				}
			}
			catch
			{
				Write-Exception $_
				Write-Warning "Unable to gather dbs for $instance"
				continue
			}
			
			foreach ($db in $dbs)
			{
				try
				{
					Write-Verbose "Querying $instance - $db"
					# Execute query against individual database and add to output
					$result = $db.ExecuteWithResults($sql).Tables.Rows
				}
				catch
				{
					Write-Exception $_
					Write-Warning "Unable to query $instance - $db"
					continue
				}
				
				foreach ($row in $result)
				{
					[pscustomobject]@{
						SqlServer = $row.SqlServer
						DatabaseName = $row.DBName
						FileName = $row.FileName
						FileGroup = $row.FileGroup
						PhysicalName = $row.PhysicalName
						UsedSpaceMB = $row.UsedSpaceMB
						FreeSpaceMB = $row.FreeSpaceMB
						FileSizeMB = $row.FileSizeMB
						PercentUsed = $row.PercentUSed
					}
				}
			}
		}
	}
}