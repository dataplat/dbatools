Function Test-DbaDatabaseCollation
{
<#
.SYNOPSIS
Compares Database Collations to Server Collation
	
.DESCRIPTION
Compares Database Collations to Server Collation
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return information for only specific databases

.PARAMETER Exclude
Return information for all but these specific databases

.PARAMETER Detailed
Shows detailed information about the server and database collations

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaDatabaseCollation

.EXAMPLE
Test-DbaDatabaseCollation -SqlServer sqlserver2014a

Returns server name, databse name and true/false if the collations match for all databases on sqlserver2014a

.EXAMPLE   
Test-DbaDatabaseCollation -SqlServer sqlserver2014a -Databases db1, db2

Returns server name, databse name and true/false if the collations match for the db1 and db2 databases on sqlserver2014a
	
.EXAMPLE   
Test-DbaDatabaseCollation -SqlServer sqlserver2014a, sql2016 -Detailed -Exclude db1

Lots of detailed information for database and server collations for all databases except db1 on sqlserver2014a and sql2016

.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2016 | Test-DbaDatabaseCollation

Returns db/server collation information for every database on every server listed in the Central Management Server on sql2016
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential,
		[switch]$Detailed
	)
	
	DynamicParam { if ($SqlServer) { return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $Credential } }
	
	BEGIN
	{
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		
		$collection = New-Object System.Collections.ArrayList
		
	}
	
	PROCESS
	{
		foreach ($servername in $SqlServer)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $Credential
			}
			catch
			{
				if ($SqlServer.count -eq 1)
				{
					throw $_
				}
				else
				{
					Write-Warning "Can't connect to $servername. Moving on."
					Continue
				}
			}
			
			$dbs = $server.Databases
			
			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.Name }
			}
			
			if ($exclude.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}
			
			
			foreach ($db in $dbs)
			{
				Write-Verbose "Processing $($db.name) on $servername"
				$null = $collection.Add([PSCustomObject]@{
					Server = $server.name
					ServerCollation = $server.collation
					Database = $db.name
					DatabaseCollation = $db.collation
					IsEqual = $db.collation -eq $server.collation
				})
			}
		}
	}
	
	END
	{
		if ($detailed)
		{
			return $collection
		}
		
		if ($databases.count -eq 1)
		{
			if ($sqlserver.count -eq 1)
			{
				return $collection.IsEqual
			}
			else
			{
				return ($collection | Select-Object Server, isEqual)
			}
		}
		else
		{
			return ($collection | Select-Object Server, Database, IsEqual)
		}
	}
}