Function Copy-SqlExtendedEvent
{
<#
.SYNOPSIS
Migrates SQL Extended Event Sessions except the two default sessions, AlwaysOn_health and system_health.

.DESCRIPTION
By default, all non-system extended events are migrated. If the event already exists on the destination, it will be skipped unless -Force is used. 
	
The -Sessions parameter is autopopulated for command-line completion and can be used to copy only specific objects.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2008 or higher.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

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

.PARAMETER Force
If sessions exists on destination server, it will be dropped and recreated.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlExtendedEvent

.EXAMPLE   
Copy-SqlExtendedEvent -Source sqlserver2014a -Destination sqlcluster

Copies all extended event sessions from sqlserver2014a to sqlcluster, using Windows credentials. 

.EXAMPLE   
Copy-SqlExtendedEvent -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

Copies all extended event sessions from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

.EXAMPLE   
Copy-SqlExtendedEvent -Source sqlserver2014a -Destination sqlcluster -WhatIf

Shows what would happen if the command were executed.
	
.EXAMPLE   
Copy-SqlExtendedEvent -Source sqlserver2014a -Destination sqlcluster -Sessions CheckQueries, MonitorUserDefinedException 

Copies two Extended Events, CheckQueries and MonitorUserDefinedException, from sqlserver2014a to sqlcluster.
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
	
	DynamicParam { if ($source) { return (Get-ParamSqlExtendedEvents -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		
		if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.XEvent") -eq $null)
		{
			throw "SMO version is too old. To migrate Extended Events, you must have SQL Server Management Studio 2008 R2 or higher installed."
		}
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		$sessions = $psboundparameters.Sessions
		
		
		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
		{
			throw "Extended Events are only supported in SQL Server 2008 and above. Quitting."
		}
	}
	process
	{
		
		$sourceSqlConn = $sourceserver.ConnectionContext.SqlConnectionObject
		$sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
		$sourceStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $sourceSqlStoreConnection
		
		$destSqlConn = $destserver.ConnectionContext.SqlConnectionObject
		$destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
		$destStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $destSqlStoreConnection
		
		$storeSessions = $sourceStore.sessions | Where-Object { $_.Name -notin 'AlwaysOn_health', 'system_health' }
		if ($sessions.length -gt 0) { $storeSessions = $storeSessions | Where-Object { $sessions -contains $_.Name } }
		
		Write-Output "Migrating sessions"
		foreach ($session in $storeSessions)
		{
			$sessionName = $session.name
			if ($deststore.sessions[$sessionName] -ne $null)
			{
				if ($force -eq $false)
				{
					Write-Warning "Extended Event Session '$sessionName' was skipped because it already exists on $destination"
					Write-Warning "Use -Force to drop and recreate"
					continue
				}
				else
				{
					if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $sessionName"))
					{
						Write-Verbose "Extended Event Session '$sessionName' exists on $destination"
						Write-Verbose "Force specified. Dropping $sessionName."
						
						try
						{
							$deststore.sessions[$sessionName].Drop()
						}
						catch
						{
							Write-Exception "Unable to drop: $_  Moving on."
							continue
						}
					}
				}
			}
			
			if ($Pscmdlet.ShouldProcess($destination, "Migrating session $sessionName"))
			{
				try
				{
					$sql = $session.ScriptCreate().GetScript() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					Write-Verbose $sql
					Write-Output "Migrating session $sessionName"
					$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
					
					if ($session.IsRunning -eq $true)
					{
						$deststore.sessions.Refresh()
						$deststore.sessions[$sessionName].Start()
					}
				}
				catch
				{
					Write-Exception $_
				}
			}
		}
	}
	
	end
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Extended Event migration finished" }
	}
}

