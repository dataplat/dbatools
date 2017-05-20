Function Copy-DbaSqlServerAgent
{
<#
.SYNOPSIS
Copies *all* ProxyAccounts, JobSchedule, SharedSchedules, AlertSystem, JobCategories, 
OperatorCategories AlertCategories, Alerts, TargetServerGroups, TargetServers, 
Operators, Jobs, Mail and general SQL Agent settings from one SQL Server Agent 
to another. $sourceserver and $destserver are SMO server objects. 

Ignores -force: does not drop and recreate.

.DESCRIPTION
This function could use some refining, as *all* job objects are copied. 

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

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

.PARAMETER DisableJobsOnDestination
When this flag is set, copy all jobs as Enabled=0

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Force
Drops and recreates the objects if it exists

.PARAMETER DisableJobsOnSource
Disables the jobs on source

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
https://dbatools.io/Copy-DbaSqlServerAgent

.EXAMPLE   
Copy-DbaSqlServerAgent -Source sqlserver2014a -Destination sqlcluster

Copies all job server objects from sqlserver2014a to sqlcluster, using Windows credentials. If job objects with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-DbaSqlServerrAgent -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

Copies all job objects from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

.EXAMPLE   
Copy-DbaSqlServerAgent -Source sqlserver2014a -Destination sqlcluster -WhatIf

Shows what would happen if the command were executed.
#>
	
	[cmdletbinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[Switch]$DisableJobsOnDestination,
		[Switch]$DisableJobsOnSource,
		[switch]$Force
		
	)
	
	BEGIN  {
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		Invoke-SmoCheck -SqlInstance $sourceserver
		Invoke-SmoCheck -SqlInstance $destserver
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		$sourceagent = $sourceserver.jobserver
	}
	
	PROCESS
	{
		
		# All of these support whatif inside of them
		Copy-DbaAgentCategory -Source $sourceserver -Destination $destserver -Force:$force
		Copy-DbaAgentOperator -Source $sourceserver -Destination $destserver -Force:$force
		Copy-DbaAgentAlert -Source $sourceserver -Destination $destserver -Force:$force -IncludeDefaults
		Copy-DbaAgentProxyAccount -Source $sourceserver -Destination $destserver -Force:$force
		Copy-DbaAgentSharedSchedule -Source $sourceserver -Destination $destserver -Force:$force
		Copy-DbaAgentJob -Source $sourceserver -Destination $destserver -Force:$force -DisableOnDestination:$DisableJobsOnDestination -DisableOnSource:$DisableJobsOnSource
		
		# To do
		<# 
			Copy-DbaAgentMasterServer -Source $sourceserver -Destination $destserver -Force:$force
			Copy-DbaAgentTargetServer -Source $sourceserver -Destination $destserver -Force:$force
			Copy-DbaAgentTargetServerGroup -Source $sourceserver -Destination $destserver -Force:$force
		#>
		
		# Here are the properties, which must be migrated seperately 
		If ($Pscmdlet.ShouldProcess($destination, "Copying Agent Properties"))
		{
			try
			{
				Write-Output "Copying SQL Agent Properties"
				$sql = $sourceagent.Script() | Out-String
				$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
				$sql = $sql -replace [Regex]::Escape("@errorlog_file="), [Regex]::Escape("--@errorlog_file=")
				Write-Verbose $sql
				$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
			}
			catch
			{
				Write-Exception $_
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Job server migration finished" }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlServerAgent
	}
}
