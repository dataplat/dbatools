Function Copy-SqlResourceGovernor
{
<#
.SYNOPSIS
Migrates Resource Pools

.DESCRIPTION
By default, all non-system resource pools are migrated. If the pool already exists on the destination, it will be skipped unless -Force is used. 
	
The -ResourcePools parameter is autopopulated for command-line completion and can be used to copy only specific objects.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

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
If policies exists on destination server, it will be dropped and recreated.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlResourceGovernor

.EXAMPLE   
Copy-SqlResourceGovernor -Source sqlserver2014a -Destination sqlcluster

Copies all extended event policies from sqlserver2014a to sqlcluster, using Windows credentials. 

.EXAMPLE   
Copy-SqlResourceGovernor -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

Copies all extended event policies from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

.EXAMPLE   
Copy-SqlResourceGovernor -Source sqlserver2014a -Destination sqlcluster -WhatIf

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
	
	DynamicParam { if ($source) { return (Get-ParamSqlResourceGovernor -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		$respools = $psboundparameters.ResourcePools
		
		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
		{
			throw "Resource Governor is only supported in SQL Server 2008 and above. Quitting."
		}
	}
	PROCESS
	{
		
		
		if ($Pscmdlet.ShouldProcess($destination, "Updating Resource Governor settings"))
		{
			if ($destserver.Edition -notmatch 'Enterprise' -and $destserver.Edition -notmatch 'Datacenter' -and $destserver.Edition -notmatch 'Developer')
			{
				Write-Warning "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor."
			}
			else
			{
				try
				{
					$sql = $sourceserver.resourceGovernor.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					Write-Verbose $sql
					Write-Output "Updating Resource Governor settings"
					$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
				}
				catch
				{
					Write-Exception $_
				}
			}
		}
		
		# Pools
		if ($respools.length -gt 0)
		{
			$pools = $sourceserver.ResourceGovernor.ResourcePools | Where-Object { $respools -contains $_.Name }
		}
		else
		{
			$pools = $sourceserver.ResourceGovernor.ResourcePools | Where-Object { $_.Name -notin "internal", "default" }
		}
		
		Write-Output "Migrating pools"
		foreach ($pool in $pools)
		{
			$poolName = $pool.name
			if ($destserver.ResourceGovernor.ResourcePools[$poolName] -ne $null)
			{
				if ($force -eq $false)
				{
					Write-Warning "Pool '$poolName' was skipped because it already exists on $destination"
					Write-Warning "Use -Force to drop and recreate"
					continue
				}
				else
				{
					if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $poolName"))
					{
						Write-Verbose "Pool '$poolName' exists on $destination"
						Write-Verbose "Force specified. Dropping $poolName."
						
						try
						{
							$destpool = $destserver.ResourceGovernor.ResourcePools[$poolName]
							$workloadgroups = $destpool.WorkloadGroups
							foreach ($workloadgroup in $workloadgroups)
							{
								$workloadgroup.Drop()
							}
							$destpool.Drop()
							$destserver.ResourceGovernor.Alter()
						}
						catch
						{
							Write-Exception "Unable to drop: $_  Moving on."
							continue
						}
					}
				}
			}
			
			if ($Pscmdlet.ShouldProcess($destination, "Migrating pool $poolName"))
			{
				try
				{
					$sql = $pool.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					Write-Verbose $sql
					Write-Output "Copying pool $poolName"
					$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
					
					$workloadgroups = $pool.WorkloadGroups
					foreach ($workloadgroup in $workloadgroups)
					{
						$workgroupname = $workloadgroup.name
						$sql = $workloadgroup.script() | Out-String
						$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
						Write-Verbose $sql
						Write-Output "Copying $workgroupname"
						$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
					}
					
				}
				catch
				{
					Write-Exception $_
				}
			}
		}
		
		if ($Pscmdlet.ShouldProcess($destination, "Reconfiguring"))
		{
			if ($destserver.Edition -notmatch 'Enterprise' -and $destserver.Edition -notmatch 'Datacenter' -and $destserver.Edition -notmatch 'Developer')
			{
				Write-Warning "The resource governor is not available in this edition of SQL Server. You can manipulate resource governor metadata but you will not be able to apply resource governor configuration. Only Enterprise edition of SQL Server supports resource governor."
			}
			else
			{
				Write-Output "Reconfiguring Resource Governor"
				$sql = "ALTER RESOURCE GOVERNOR RECONFIGURE"
				$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
			}
		}
		
	}
	
	end
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message"))
		{
			Write-Output "Resource Governor migration finished"
		}
	}
	
}