Function Test-DbaServerName
{
<#
.SYNOPSIS
Tests to see if it's possible to easily rename the server at the SQL Server instance level
	
.DESCRIPTION
	
https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

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

If $true is returned, sqlserver2014a passes the test, meaning it's properly named

.EXAMPLE   
Test-DbaServerName -SqlServer sqlserver2014a, sql2016

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
		[switch]$Detailed,
		[switch]$NoWarning
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
				Write-Warning "$servername is a cluster. Repair-DbaServerName does not support clusters."
			}
			
			$sqlservername = $server.ConnectionContext.ExecuteScalar("select @@servername")
			$instance = $server.InstanceName
			
			if ($instance.length -eq 0)
			{
				$serverinstancename = $server.NetName
				$instance = "MSSQLSERVER"
			}
			else
			{
				$netname = $server.NetName
				$serverinstancename = "$netname\$instance"
			}
			
			$serverinfo = [PSCustomObject]@{
				ServerInstanceName = $serverinstancename
				SqlServerName = $sqlservername
				IsEqual = $serverinstancename -eq $sqlservername
				RenameRequired = $serverinstancename -ne $sqlservername
			}
			
			if ($Detailed)
			{
				$reasons = @()
				$servicename = "SQL Server Reporting Services ($instance)"
				
				try
				{
					$rs = Get-Service -ComputerName $server.ComputerNamePhysicalNetBIOS -DisplayName $servicename -ErrorAction SilentlyContinue
				}
				catch
				{
					if ($NoWarnings -eq $false)
					{
						Write-Warning "Can't contact $($server.ComputerNamePhysicalNetBIOS) using Get-Service. This means the script will not be able to automatically restart SQL services."
					}
				}
				
				if ($rs.count -gt 0)
				{
					$rstext = "Reporting Services must be stopped and updated"
					$serverinfo | Add-Member -NotePropertyName Warnings -NotePropertyValue $rstext
				}
				
				# check for mirroring
				$mirroreddb = $server.Databases | Where-Object { $_.IsMirroringEnabled -eq $true }
				
				if ($mirroreddb.count -gt 0)
				{
					$dbs = $mirroreddb.name -join ", "
					$reasons += "Databases are being mirrored: $dbs"
				}
				
				# check for replication
				$sql = "select name from sys.databases where is_published = 1 or is_subscribed =1 or is_distributor = 1"
				$replicatedb = $server.ConnectionContext.ExecuteWithResults($sql).Tables
				
				if ($replicatedb.name.count -gt 0)
				{
					$dbs = $replicatedb.name -join ", "
					$reasons += "Databases are involved in replication: $dbs"
				}
				
				# check for even more replication
				$sql = "select srl.remote_name as RemoteLoginName from sys.remote_logins srl join sys.sysservers sss on srl.server_id = sss.srvid"
				$results = $server.ConnectionContext.ExecuteWithResults($sql).Tables
				
				if ($results.RemoteLoginName.count -gt 0)
				{
					$remotelogins = $results.RemoteLoginName -join ", "
					$reasons += "Remote logins still exist: $remotelogins"
					
				}
				
				if ($reasons.count -gt 0)
				{
					$serverinfo | Add-Member -NotePropertyName Updatable -NotePropertyValue $false
					$serverinfo | Add-Member -NotePropertyName Errors -NotePropertyValue $reasons
				}
				else
				{
					$serverinfo | Add-Member -NotePropertyName Updatable -NotePropertyValue $true
				}
			}
			
			$null = $collection.Add($serverinfo)
		}
	}
	
	END
	{
		return $collection
	}
}