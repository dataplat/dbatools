function Test-DbaVirtualLogFile
{
<#
.SYNOPSIS
Returns database virtual log file information for database files on a SQL instance.

.DESCRIPTION
As you may already know, having a TLog file with too many VLFs can hurt database performance.

Too many virtual log files can cause transaction log backups to slow down and can also slow down database recovery and, in extreme cases, even affect insert/update/delete performance. 

	References:
    http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
    http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx

If you've got a high number of VLFs, you can use Expand-SqlTLogResponsibly to reduce the number.

.PARAMETER SqlServer
SQLServer name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input.

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, current Windows login will be used.

.PARAMETER IncludeSystemDBs
Switch parameter that when used will display system database information
	
.PARAMETER Databases
Specify one or more databases to process. 

.PARAMETER Exclude
Specify one or more databases to exclude.

.PARAMETER Detailed
Returns all information provided by DBCC LOGINFO plus the server name and database name
	
.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
	
.LINK
https://dbatools.io/Test-DbaVirtualLogFile

.EXAMPLE
Test-DbaVirtualLogFile -SqlServer sqlcluster

Returns all user database virtual log file counts for the sqlcluster instance

.EXAMPLE
Test-DbaVirtualLogFile -SqlServer sqlserver | Where-Object {$_.Count -ge 50}

Returns user databases that have more than or equal to 50 VLFs

.EXAMPLE
@('sqlserver','sqlcluster') | Test-DbaVirtualLogFile

Returns all VLF information for the sqlserver and sqlcluster SQL Server instances. Processes data via the pipeline.

.EXAMPLE
Test-DbaVirtualLogFile -SqlServer sqlcluster -Databases db1, db2

Returns VLF counts for the db1 and db2 databases on sqlcluster. 
#>
	[CmdletBinding()]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$IncludeSystemDBs,
		[switch]$Detailed
	)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		$collection = New-Object System.Collections.ArrayList
	}
	
	PROCESS
	{
		foreach ($servername in $SqlServer)
		{
			#For each SQL Server in collection, connect and get SMO object
			Write-Verbose "Connecting to $servername"
			$server = Connect-SqlServer $servername -SqlCredential $SqlCredential
			
			#If IncludeSystemDBs is true, include systemdbs
			#only look at online databases (Status equal normal)
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
				Write-Warning "Unable to gather dbs for $servername"
				continue
			}
			
			foreach ($db in $dbs)
			{
				try
				{
					Write-Verbose "Querying $($db.name) on $servername."
					#Execute query against individual database and add to output
					
					if ($Detailed -eq $true)
					{
						$table = New-Object System.Data.Datatable
						$servercolumn = $table.Columns.Add("Server")
						$servercolumn.DefaultValue = $server.name
						$dbcolumn = $table.Columns.Add("Database")
						$dbcolumn.DefaultValue = $db.name
						
						$temptable = $db.ExecuteWithResults("DBCC LOGINFO").Tables
						
						foreach ($column in $temptable.Columns)
						{
							$null = $table.Columns.Add($column.ColumnName)
						}
						
						foreach ($row in $temptable.rows)
						{
							$table.ImportRow($row)
						}
						
						$null = $collection.Add($table)
					}
					else
					{
						$null = $collection.Add([PSCustomObject]@{
								Server = $server.name
								Database = $db.name
								Count = $db.ExecuteWithResults("DBCC LOGINFO").Tables.Rows.Count
							})
					}
				}
				catch
				{
					Write-Exception $_
					Write-Warning "Unable to query $($db.name) on $servername"
					continue
				}
			}
		}
	}
	END
	{
		return $collection
	}
}
