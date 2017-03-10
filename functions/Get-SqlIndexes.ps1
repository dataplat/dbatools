Function Get-SqlIndexes
{
<#
.SYNOPSIS
Get a list of indexes

.DESCRIPTION
This command returns the indexes of a database or of a list of databases. 

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.NOTES
Tags: Maintenance
Author: Steffen Kampmann: https://github.com/abbgrade

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Get-SqlIndexes

.EXAMPLE
Get-SqlIndexes.ps1 -SqlServer "(localdb)\MSSQLLocalDB", "(localdb)\v11.0"
Returns all indexes for localdb instances MSSQLLocalDB and v11.0.

#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer
	)

	BEGIN
	{
		$systemDatabases = "master", "model", "msdb", "tempdb"
	
		$sql = "
SELECT
		DB_NAME() AS 'DbName',
		dbschemas.[name] AS 'Schema',
		dbtables.[name] AS 'Table',
		dbindexes.[name] AS 'Index',
		indexstats.avg_fragmentation_in_percent AS 'FragmentationPct',
		indexstats.page_count AS 'PageCount',
		dbindexes.[type_desc] AS 'TypeDesc',
		dbindexes.is_primary_key AS 'IsPrimaryKey',
		dbindexes.is_unique_constraint AS 'IsUniqueConstraint',
		dbindexes.filter_definition AS 'FilterDefinition'
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
JOIN sys.tables dbtables ON
		dbtables.[object_id] = indexstats.[object_id]
JOIN sys.schemas dbschemas ON
		dbtables.[schema_id] = dbschemas.[schema_id]
JOIN sys.indexes AS dbindexes ON
		dbindexes.[object_id] = indexstats.[object_id] AND
		indexstats.index_id = dbindexes.index_id
ORDER BY
		1,2,3,4"
	}

	PROCESS
	{   

		foreach ($instance in $SqlServer)
		{
	
			try
			{
				Write-Verbose "Connecting to $instance"
				$server = Connect-DbaSqlServer -SqlServer $instance
			}
			catch
			{
				Write-Warning "Failed to connect to: $server"
				continue
			}

			$databases = Invoke-Sqlcmd -ServerInstance $server -Query "SELECT name FROM master.dbo.sysdatabases" | Where { $systemDatabases -notcontains $_.name }
			foreach ($database in $databases)
			{
				$indexes = Invoke-Sqlcmd -ServerInstance $server -Database $database.name -Query $sql
				foreach ( $index in $indexes )
				{
					[PSCustomObject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.Name
						DbName = $index.DbName
						Schema = $index.Schema
						Index = $index.Index
						FragmentationPct = $index.FragmentationPct
						PageCount = $index.PageCount
						TypeDesc = $index.TypeDesc
						IsPrimaryKey = $index.IsPrimaryKey
						IsUniqueConstraint = $index.IsUniqueConstraint
						FilterDefinition = $index.FilterDefinition
					}
				}
			}
		}
	}
}