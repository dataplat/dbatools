Function Test-DbaServerName
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
https://dbatools.io/Test-DbaServerName

.EXAMPLE
Test-DbaServerName -SqlServer sqlserver2014a

Returns server name, databse name and true/false if the collations match for all databases on sqlserver2014a

.EXAMPLE   
Test-DbaServerName -SqlServer sqlserver2014a -Databases db1, db2

Returns server name, databse name and true/false if the collations match for the db1 and db2 databases on sqlserver2014a
	
.EXAMPLE   
Test-DbaServerName -SqlServer sqlserver2014a, sql2016 -Detailed -Exclude db1

Lots of detailed information for database and server collations for all databases except db1 on sqlserver2014a and sql2016

.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2016 | Test-DbaServerName

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
	
	BEGIN
	{
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
			
			
			if ($server.isClustered)
			{
				if ($SqlServer.count -eq 1)
				{
					# If we ever decide with a -Force to support a cluster name change
					# We would compare $server.NetName, and never ComputerNamePhysicalNetBIOS
					throw "$servername is a cluster. Not messing with that."
				}
				else
				{
					Write-Warning "$servername is a cluster. Not messing with that."
					Continue
				}
			}
			
			$sqlservername = $server.ConnectionContext.ExecuteScalar("select @@servername")
			
			$serverinfo = [PSCustomObject]@{
				ServerName = $server.NetName
				SqlServerName = $sqlservername
				IsEqual = $server.NetName -eq $sqlservername
			}
			
			if ($Detailed)
			{
				#Replication
				$serverinfo | Add-Member -NotePropertyName CanChange -NotePropertyValue $canchange
				
				if ($canchange -eq $false)
				{
					$serverinfo | Add-Member -NotePropertyName Reason -NotePropertyValue "Replication is prohibiting a server name change"
				}
				
			}
			
			$null = $collection.Add($serverinfo)
		}
	}
	
	END
	{
		if ($Detailed -eq $true)
		{
			return $collection
		}
		
		if ($sqlserver.count -eq 1)
		{
			return $collection.IsEqual
		}
		else
		{
			return ($collection | Select-Object Server, isEqual)
		}
	}
}