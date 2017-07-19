Function Get-DbaModule {
<# 
	.SYNOPSIS 
	Displays all objects in sys.sys_modules after specified modification date.  Works on SQL Server 2008 and above.
	
	.DESCRIPTION 
	Quickly find modules (Stored Procs, Functions, Views, Constraints, Rules, Triggers, etc) that have been modified in a database, or across all databases.
	Results will exclude the module definition, but can be queried explicitly.
	
	.PARAMETER SqlInstance
	Allows you to specify a comma separated list of servers to query.
	
	.PARAMETER SqlCredential
	Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
	$cred = Get-Credential, this pass this $cred to the param. 
	Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.  
	
	.PARAMETER ModifiedSince
	DateTime value to use as minimum modified date of module.
	
	.PARAMETER NoSystemDb
	Allows you to suppress output on system databases
	
	.PARAMETER NoSystemObjects
	Allows you to suppress output on system objects
	
	.NOTES 
	Author: Brandon Abshire, netnerds.net
	Tags: StoredProcedure, Trigger
	dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
	Copyright (C) 2016 Chrissy LeMaire
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
	
	.LINK 
	https://dbatools.io/Get-DbaModule
	
	.EXAMPLE   
	Get-DbaModule -SqlServer sql2008, sqlserver2012
	Return all modules for servers sql2008 and sqlserver2012 sorted by Database, Modify_Date ASC
	
	.EXAMPLE   
	Get-DbaModule -SqlServer sql2008 -Database TestDB -ModifiedSince "01/01/2017 10:00:00 AM"
	Return all modules on server sql2008 for only the TestDB database with a modified date after 01/01/2017 10:00:00 AM
#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[datetime]$ModifiedSince = "01/01/1900",
		[switch]$NoSystemDb,
		[switch]$NoSystemObjects
	)
	
	begin {
			
		$sql = "SELECT  DB_NAME() AS DatabaseName,
        so.name AS ModuleName,
        so.object_id ,
        SCHEMA_NAME(so.schema_id) AS SchemaName ,
        so.parent_object_id ,
        so.type ,
        so.type_desc ,
        so.create_date ,
        so.modify_date ,
        so.is_ms_shipped ,
        sm.definition
		FROM sys.sql_modules sm
        LEFT JOIN sys.objects so ON sm.object_id = so.object_id
        WHERE so.modify_date >= '$($ModifiedSince)'"
		if ($NoSystemObjects) {
			$sql += "`n AND so.is_ms_shipped = 0"
		}
		$sql += "`n ORDER BY so.modify_date"
	}
	
	PROCESS {
		
		foreach ($instance in $SqlInstance) {
			Write-Verbose "Attempting to connect to $instance"
			try {
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
			}
			catch {
				Write-Warning "Can't connect to $instance or access denied. Skipping."
				continue
			}
			
			if ($server.versionMajor -lt 10) {
				Write-Warning "This function does not support versions lower than SQL Server 2008 (v10). Skipping server $instance."
				
				Continue
			}
			
			
			$dbs = $server.Databases
			
			if ($databases.count -gt 0) {
				$dbs = $dbs | Where-Object { $databases -contains $_.Name }
			}
			
			if ($NoSystemDb) {
				$dbs = $dbs | Where-Object { $_.IsSystemObject -eq $false }
			}
			
			if ($exclude.count -gt 0) {
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}
			
			foreach ($db in $dbs) {
				Write-Verbose "Processing $db on $instance"
				
				if ($db.IsAccessible -eq $false) {
					Write-Warning "The database $db is not accessible. Skipping database."
					Continue
				}
				
				foreach ($row in $db.ExecuteWithResults($sql).Tables[0]) {
					[PSCustomObject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $row.DatabaseName
						ModuleName = $row.ModuleName
						ObjectID = $row.object_id
						SchemaName = $row.SchemaName
						Type_Desc = $row.type_desc
						Create_Date = $row.create_date
						Modify_Date = $row.modify_date
						is_ms_shipped = $row.is_ms_shipped
						Definition = $row.definition
					} | Select-DefaultView -ExcludeProperty Definition
				}
			}
		}
	}
}
