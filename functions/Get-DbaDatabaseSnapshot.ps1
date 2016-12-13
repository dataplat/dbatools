Function Get-DbaDatabaseSnapshot
{
<#
.SYNOPSIS
Get database snapshots with details

.DESCRIPTION
Retrieves the list of database snapshot available, along with their base (the db they are the snapshot of) and creation time

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return information for only specific base dbs

.PARAMETER Exclude
Return information for all but these specific base dbs

.NOTES
Author: niphlod

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Get-DbaDatabaseSnapshot

.EXAMPLE
Get-DbaDatabaseSnapshot -SqlServer sqlserver2014a

Returns a custom object displaying Server, Database, DatabaseCreated, SnapshotOf

.EXAMPLE
Get-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Databases HR, Accounting

Returns informations for database snapshots having HR and Accounting as base dbs

.EXAMPLE
Get-DbaDatabaseSnapshot -SqlServer sqlserver2014a -Exclude HR

Returns informations for database snapshots excluding ones that have HR as base dbs


#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential
	)

	DynamicParam {
		if ($SqlServer) {
			return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $Credential -DbsWithSnapshotsOnly
		}
	}

	BEGIN
	{
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
	}

	PROCESS
	{
		foreach ($servername in $SqlServer)
		{
			Write-Verbose "Connecting to $servername"
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $Credential
				
			}
			catch
			{
				Write-Warning "Can't connect to $servername"
				Continue
			}
			
			$dbs = $server.Databases | Where-Object IsDatabaseSnapshot -eq $true | Sort-Object DatabaseSnapshotBaseName, Name

			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.DatabaseSnapshotBaseName }
			}

			if ($exclude.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.DatabaseSnapshotBaseName }
			}


			foreach ($db in $dbs)
			{
				$object = [PSCustomObject]@{
					Server = $server.name
					Database = $db.name
					SnapshotOf = $db.DatabaseSnapshotBaseName
					DatabaseCreated = $db.createDate
					SnapshotDb = $db
				}
				
				Select-DefaultField -InputObject $object -Property 'Server', 'Database', 'SnapshotOf', 'DatabaseCreated'
			}
		}
	}
}
