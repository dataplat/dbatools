Function Repair-DbaServerName
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
https://dbatools.io/Repair-DbaServerName

.EXAMPLE
Repair-DbaServerName -SqlServer sqlserver2014a

Returns server name, databse name and true/false if the collations match for all databases on sqlserver2014a

.EXAMPLE   
Repair-DbaServerName -SqlServer sqlserver2014a -Databases db1, db2

Returns server name, databse name and true/false if the collations match for the db1 and db2 databases on sqlserver2014a
	
.EXAMPLE   
Repair-DbaServerName -SqlServer sqlserver2014a, sql2016 -Detailed -Exclude db1

Lots of detailed information for database and server collations for all databases except db1 on sqlserver2014a and sql2016

.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2016 | Repair-DbaServerName

Returns db/server collation information for every database on every server listed in the Central Management Server on sql2016
	
#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential,
		[switch]$Force
	)
	
	BEGIN
	{
		# if ($AutoFix -eq $true) { $ConfirmPreference = "High" }
		if ($Force -eq $true) { $ConfirmPreference = "None" }
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
			
			# Check to see if we can easily proceed
			Write-Verbose "Executing Test-DbaServerName to see if the server is in a state to be renamed. "
			
			$nametest = Test-DbaServerName $servername -Detailed
			
			$serverinstancename = $nametest.ServerInstanceName
			$sqlservername = $nametest.SqlServerName
			
			if ($serverinstancename -eq $sqlservername)
			{
				return "$serverinstancename's @@SERVERNAME is perfect :) If you'd like to rename it, first rename the Windows server."
			}
			
			if ($nametest.updatable -eq $false)
			{
				Write-Output "Test-DbaServerName reports that the rename cannot proceed with a rename in this $servername's current state."
				
				$nametest
				
				foreach ($nametesterror in $nametest.Errors)
				{
					if ($nametesterror -like '*replication*')
					{
						$replication = $true
						throw "Cannot proceed because some databases are involved in replication. You can run exec sp_dropdistributor @no_checks = 1 but that may be pretty dangerous. We may offer an AutoFix with confirmation prompts in the future. Let usk know if you're interested."
					}
					elseif ($Error -like '*mirror*')
					{
						throw "Cannot proceed because some databases are being mirrored. Stop mirroring to proceed. We may offer an AutoFix with confirmation prompts in the future. Let usk know if you're interested."
					}
				}
			}
			
			if ($nametest.Warnings.length -gt 0)
			{
				$instancename = $instance = $server.InstanceName
				if ($instance.length -eq 0) { $instance = "MSSQLSERVER" }
				
				$allsqlservices = Get-Service -ComputerName $server.ComputerNamePhysicalNetBIOS -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "SQL*$instance*" -and $_.Status -eq "Running" }
				$reportingservice = Get-Service -ComputerName $server.ComputerNamePhysicalNetBIOS -DisplayName "SQL Server Reporting Services ($instance)" -ErrorAction SilentlyContinue
				
				if ($reportingservice.Status -eq "Running")
				{
					if ($Pscmdlet.ShouldProcess($server.name, "Reporting Services is running for this instance. Would you like to automatically stop this service?"))
					{
						$reportingservice | Stop-Service
						Write-Warning "You must reconfigure Reporting Services using Reporting Services Configuration Manager or PowerShell once the server has been successfully renamed."
					}
				}
			}
			
			if ($Pscmdlet.ShouldProcess($server.name, "Performing sp_dropserver to remove the old server name, $sqlservername, then sp_addserver to add $serverinstancename"))
			{
				$sql = "sp_dropserver '$sqlservername'"
				try
				{
					$null = $server.ConnectionContext.ExecuteNonQuery($sql)
					Write-Output "Successfully executed $sql"
				}
				catch
				{
					Write-Exception $_
					throw $_
				}
				
				$sql = "sp_addserver '$serverinstancename', local"
				
				try
				{
					$null = $server.ConnectionContext.ExecuteNonQuery($sql)
					Write-Output "Successfully executed $sql"
				}
				catch
				{
					Write-Exception $_
					throw $_
				}
			}
			
			if ($Pscmdlet.ShouldProcess($server.ComputerNamePhysicalNetBIOS, "Rename complete! The SQL Service must be restarted to commit the changes. Would you like to restart this instance now?"))
			{
				try
				{
					$allsqlservices | Stop-Service -Force
					$allsqlservices | Start-Service
				}
				catch
				{
					Write-Exception $_
					throw "Could not restart SQL Service :("
				}
			}
		}
	}
	
	END
	{
		
	}
}