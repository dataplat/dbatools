Function Copy-SqlPolicyManagement
{
<#
.SYNOPSIS
Migrates SQL Policy Based Management Objects

.DESCRIPTION
Coming soon

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source Sql Server. You must have sysadmin access and server version must be > Sql Server 2005.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be > Sql Server 2005.

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
If policies exists and remote server, it will be dropped and recreated.

.NOTES 
Author  : Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (http://git.io/b3oo, clemaire@gmail.com)
Copyright (C) 2105 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.


.EXAMPLE   
Copy-SqlPolicyManagement -Source sqlserver2014a -Destination sqlcluster

Copies all extended event policies from sqlserver2014a to sqlcluster, using Windows credentials. 

.EXAMPLE   
Copy-SqlPolicyManagement -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

Copies all extended event policies from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster.

.EXAMPLE   
Copy-SqlPolicyManagement -Source sqlserver2014a -Destination sqlcluster -WhatIf

Shows what would happen if the command were executed.
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
	
	DynamicParam { if ($source) { return (Get-ParamSqlPolicyManagement -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	process
	{
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.name
		$destination = $destserver.name
		$policies = $psboundparameters.policies
		$conditions = $psboundparameters.conditions
		
		if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
		if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
		
		$sourceSqlConn = $sourceserver.ConnectionContext.SqlConnectionObject
		$sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
		$sourceStore = New-Object  Microsoft.SqlServer.Management.DMF.PolicyStore $sourceSqlStoreConnection
		
		$destSqlConn = $destserver.ConnectionContext.SqlConnectionObject
		$destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
		$destStore = New-Object  Microsoft.SqlServer.Management.DMF.PolicyStore $destSqlStoreConnection
		
		$storepolicies = $sourceStore.policies
		$storeconditions = $sourceStore.conditions
		if ($policies.length -gt 0) { $storepolicies = $storepolicies | Where-Object { $policies -contains $_.Name } }
		if ($conditions.length -gt 0) { $storeconditions = $storeconditions | Where-Object { $conditions -contains $_.Name } }
		
		if ($policies.length -gt 0 -and $conditions.length -eq 0) { $storeconditions = $null }
		if ($conditions.length -gt 0 -and $policies.length -eq 0) { $storepolicies = $null }
		
		<# 
						Policies
		#>
		Write-Output "Migrating policies"
		foreach ($policy in $storepolicies)
		{
			$policyName = $policy.name
			if ($deststore.policies[$policyName] -ne $null)
			{
				if ($force -eq $false)
				{
					Write-Warning "Policy '$policyName' was skipped because it already exists on $destination"
					Write-Warning "Use -Force to drop and recreate"
					continue
				}
				else
				{
					if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $policyName"))
					{
						Write-Output "Policy '$policyName' exists on $destination"
						Write-Output "Force specified. Dropping $policyName."
						
						try
						{
							$deststore.policies[$policyName].Drop()
						}
						catch
						{
							Write-Exception "Unable to drop: $_  Moving on."
							continue
						}
					}
				}
			}
			
			if ($Pscmdlet.ShouldProcess($destination, "Migrating policy $policyName"))
			{
				try
				{
					$sql = $policy.ScriptCreate().GetScript()
					Write-Verbose $sql
					$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
				}
				catch
				{
					Write-Exception $_
				}
			}
		}
		
		<# 
						Conditions
		#>
		Write-Output "Migrating conditions"
		foreach ($condition in $storeconditions)
		{
			$conditionName = $condition.name
			if ($deststore.conditions[$conditionName] -ne $null)
			{
				if ($force -eq $false)
				{
					Write-Warning "condition '$conditionName' was skipped because it already exists on $destination"
					Write-Warning "Use -Force to drop and recreate"
					continue
				}
				else
				{
					if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $conditionName"))
					{
						Write-Output "condition '$conditionName' exists on $destination"
						Write-Output "Force specified. Dropping $conditionName."
						
						try
						{
							$deststore.conditions[$conditionName].Drop()
						}
						catch
						{
							Write-Exception "Unable to drop: $_  Moving on."
							continue
						}
					}
				}
			}
			
			if ($Pscmdlet.ShouldProcess($destination, "Migrating condition $conditionName"))
			{
				try
				{
					$sql = $condition.ScriptCreate().GetScript()
					Write-Verbose $sql
					$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
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

