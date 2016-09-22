Function Test-DbaDatabaseCompatibility
{
<#
.SYNOPSIS
Compares Database Compatibility level to Server Compatibility
	
.DESCRIPTION
Compares Database Compatibility level to Server Compatibility
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return information for only specific databases

.PARAMETER Exclude
Return information for all but these specific databases

.PARAMETER Detailed
Shows detailed information about the server and database compatibility level

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Test-DbaDatabaseCompatibility

.EXAMPLE
Test-DbaDatabaseCompatibility -SqlServer sqlserver2014a

Returns server name, databse name and true/false if the compatibility level match for all databases on sqlserver2014a

.EXAMPLE   
Test-DbaDatabaseCompatibility -SqlServer sqlserver2014a -Databases db1, db2

Returns server name, databse name and true/false if the compatibility level match for the db1 and db2 databases on sqlserver2014a
	
.EXAMPLE   
Test-DbaDatabaseCompatibility -SqlServer sqlserver2014a, sql2016 -Detailed -Exclude db1

Lots of detailed information for database and server compatibility level for all databases except db1 on sqlserver2014a and sql2016

.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2014 | Test-DbaDatabaseCompatibility

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
			Write-Verbose "Connecting to $servername"
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
			
			$serverversion = "Version$($server.VersionMajor)0"
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
						ServerLevel = $serverversion
						Database = $db.name
						DatabaseCollation = $db.CompatibilityLevel
						IsEqual = $db.CompatibilityLevel -eq $serverversion
					})
			}
		}
	}
	
	END
	{
		if ($Detailed -eq $true)
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