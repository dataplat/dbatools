Function Test-DbaServerName
{
<#
.SYNOPSIS
Tests to see if it's possible to easily rename the server at the SQL Server instance level, or if it even needs to be changed.
	
.DESCRIPTION
When a SQL Server's host OS is renamed, the SQL Server should be as well. This helps with Availability Groups and Kerberos.

This command helps determine if your OS and SQL Server names match, and thus, if a rename is required.
	
It then checks conditions that would prevent a rename like database mirroring and replication.
		
https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user.

.PARAMETER Detailed
Specifies if the servername is updatable. If updatable -eq $false, it will return the reasons why.

.PARAMETER NoWarnings
This is an internal parameter used by Repair-DbaServerName which produces warnings of its own.

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

Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a.

.EXAMPLE   
Test-DbaServerName -SqlServer sqlserver2014a, sql2016

Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016.

.EXAMPLE   
Test-DbaServerName -SqlServer sqlserver2014a, sql2016 -Detailed

Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016.
	
If a Rename is required, it will also show Updatable, and Reasons if the servername is not updatable.

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
		$servercount++
		
		foreach ($servername in $SqlServer)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $Credential
			}
			catch
			{
				if ($servercount -eq 1 -and $SqlServer.count -eq 1) # This helps with handling servernames being passed via commandline or via pipeline
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
				Write-Warning "$servername is a cluster. Renaming clusters is not supported by Microsoft."
			}
			
			if ($server.VersionMajor -eq 8)
			{
				if ($servercount -eq 1 -and $SqlServer.count -eq 1)
				{
					throw "SQL Server 2000 not supported."
				}
				else
				{
					Write-Warning "SQL Server 2000 not supported. Skipping $servername."
					Continue
				}
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
				$netbiosname = $server.ComputerNamePhysicalNetBIOS
				Write-Verbose "Checking for $servicename on $netbiosname"
				$rs = $null
				
				try
				{
					 $rs = Get-Service -ComputerName $netbiosname -DisplayName $servicename -ErrorAction SilentlyContinue
				}
				catch
				{
					if ($NoWarnings -eq $false)
					{
						Write-Warning "Can't contact $netbiosname using Get-Service. This means the script will not be able to automatically restart SQL services."
					}
				}
				
				if ($rs.length -gt 0)
				{
					if ($rs.Status -eq 'Running')
					{
						$rstext = "Reporting Services must be stopped and updated."
					}
					else
					{
						$rstext = "Reporting Services exists. When it is started again, it must be updated."
					}
					$serverinfo | Add-Member -NotePropertyName Warnings -NotePropertyValue $rstext
				}
				
				# check for mirroring
				$mirroreddb = $server.Databases | Where-Object { $_.IsMirroringEnabled -eq $true }
				
				Write-Debug "Found the following mirrored dbs: $($mirroreddb.name)"
				
				if ($mirroreddb.length -gt 0)
				{
					$dbs = $mirroreddb.name -join ", "
					$reasons += "Databases are being mirrored: $dbs"
				}
				
				# check for replication
				$sql = "select name from sys.databases where is_published = 1 or is_subscribed =1 or is_distributor = 1"
				Write-Debug $sql
				$replicatedb = $server.ConnectionContext.ExecuteWithResults($sql).Tables
				
				if ($replicatedb.name.length -gt 0)
				{
					$dbs = $replicatedb.name -join ", "
					$reasons += "Databases are involved in replication: $dbs"
				}
				
				# check for even more replication
				$sql = "select srl.remote_name as RemoteLoginName from sys.remote_logins srl join sys.sysservers sss on srl.server_id = sss.srvid"
				Write-Debug $sql
				$results = $server.ConnectionContext.ExecuteWithResults($sql).Tables
				
				if ($results.RemoteLoginName.length -gt 0)
				{
					$remotelogins = $results.RemoteLoginName -join ", "
					$reasons += "Remote logins still exist: $remotelogins"
				}
				
				if ($reasons.length -gt 0)
				{
					$serverinfo | Add-Member -NotePropertyName Updatable -NotePropertyValue $false
					$serverinfo | Add-Member -NotePropertyName Blockers -NotePropertyValue $reasons
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