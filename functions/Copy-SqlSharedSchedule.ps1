Function Copy-SqlSharedSchedule
{
<#
.SYNOPSIS 
Copy-SqlSharedSchedule migrates shared job schedules from one SQL Server to another. 

.DESCRIPTION
By default, all shared job schedules are copied. The -SharedSchedules parameter is autopopulated for command-line completion and can be used to copy only specific shared job schedules.

If the associated credential for the account does not exist on the destination, it will be skipped. If the shared job schedule already exists on the destination, it will be skipped unless -Force is used.  

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

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlSharedSchedule

.EXAMPLE   
Copy-SqlSharedSchedule -Source sqlserver2014a -Destination sqlcluster

Copies all shared job schedules from sqlserver2014a to sqlcluster, using Windows credentials. If shared job schedules with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlSharedSchedule -Source sqlserver2014a -Destination sqlcluster -SharedSchedule Weekly -SourceSqlCredential $cred -Force

Copies a single shared job schedule, the Weekly shared job schedule from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a shared job schedule with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-SqlSharedSchedule -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
	)
	DynamicParam { if ($source) { return (Get-ParamSqlSharedSchedules -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		$schedules = $psboundparameters.SharedSchedules
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
		{
			throw "Server SharedSchedules are only supported in SQL Server 2005 and above. Quitting."
		}
		
		$serverschedules = $sourceserver.JobServer.SharedSchedules
		$destschedules = $destserver.JobServer.SharedSchedules
	}
	PROCESS
	{
		foreach ($schedule in $serverschedules)
		{
			$schedulename = $schedule.name
			if ($schedules.length -gt 0 -and $schedules -notcontains $schedulename) { continue }
			
			if ($destschedules.name -contains $schedulename)
			{
				if ($force -eq $false)
				{
					Write-Warning "Shared job schedule $schedulename exists at destination. Use -Force to drop and migrate."
					continue
				}
				else
				{
					if ($destserver.JobServer.jobs.Jobschedules.name -contains $schedulename)
					{ 
						Write-Warning "Schedule $schedulename has associated jobs. Skipping."
						continue
					}
					else 
					{
					
						if ($Pscmdlet.ShouldProcess($destination, "Dropping schedule $schedulename and recreating"))
						{
							try
							{
								Write-Verbose "Dropping schedule $schedulename"
								$destserver.JobServer.SharedSchedules[$schedulename].Drop()
							}
							catch 
							{ 
								Write-Exception $_ 
								continue
							}
						}
					}
				}
			}

			If ($Pscmdlet.ShouldProcess($destination, "Creating schedule $schedulename"))
			{
				try
				{
					Write-Output "Copying schedule $schedulename"
					$sql = $schedule.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
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
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Job schedule migration finished" }
	}
}