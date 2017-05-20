function Copy-DbaServerTrigger
{
<#
.SYNOPSIS 
Copy-DbaServerTrigger migrates server triggers from one SQL Server to another. 

.DESCRIPTION
By default, all triggers are copied. The -ServerTriggers parameter is autopopulated for command-line completion and can be used to copy only specific triggers.

If the trigger already exists on the destination, it will be skipped unless -Force is used. 

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Force
Drops and recreates the Trigger if it exists

.NOTES
Tags: Migration
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-DbaServerTrigger

.EXAMPLE   
Copy-DbaServerTrigger -Source sqlserver2014a -Destination sqlcluster

Copies all server triggers from sqlserver2014a to sqlcluster, using Windows credentials. If triggers with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-DbaServerTrigger -Source sqlserver2014a -Destination sqlcluster -ServerTrigger tg_noDbDrop -SourceSqlCredential $cred -Force

Copies a single trigger, the tg_noDbDrop trigger from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a trigger with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-DbaServerTrigger -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
	)

	
	BEGIN
	{
		$triggers = $psboundparameters.Triggers
		
		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
		{
			throw "Server Triggers are only supported in SQL Server 2005 and above. Quitting."
		}
		
		$servertriggers = $sourceserver.Triggers
		$desttriggers = $destserver.Triggers
		
	}
	PROCESS
	{
		foreach ($trigger in $servertriggers)
		{
			$triggername = $trigger.name
			if ($triggers.length -gt 0 -and $triggers -notcontains $triggername) { continue }
			
			if ($desttriggers.name -contains $triggername)
			{
				if ($force -eq $false)
				{
					Write-Warning "Server trigger $triggername exists at destination. Use -Force to drop and migrate."
					continue
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($destination, "Dropping server trigger $triggername and recreating"))
					{
						try
						{
							Write-Verbose "Dropping server trigger $triggername"
							$destserver.triggers[$triggername].Drop()
						}
						catch { 
							Write-Exception $_ 
							continue
						}
					}
				}
			}

			If ($Pscmdlet.ShouldProcess($destination, "Creating server trigger $triggername"))
			{
				try
				{
					Write-Output "Copying server trigger $triggername"
					$sql = $trigger.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					$sql = $sql -replace "CREATE TRIGGER", "`nGO`nCREATE TRIGGER"
					$sql = $sql -replace "ENABLE TRIGGER", "`nGO`nENABLE TRIGGER"
					
					Write-Verbose $sql
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch
				{
					Write-Exception $_
				}
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Server trigger migration finished" }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlServerTrigger
	}
}
