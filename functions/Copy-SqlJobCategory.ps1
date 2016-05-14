Function Copy-SqlJobCategory
{
<#
.SYNOPSIS 
Copy-SqlJobCategory migrates job categories from one SQL Server to another. 

.DESCRIPTION
By default, all job categories are copied. The -JobCategories parameter is autopopulated for command-line completion and can be used to copy only specific job categories.

If the associated credential for the category does not exist on the destination, it will be skipped. If the job category already exists on the destination, it will be skipped unless -Force is used.  

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

.LINK
https://dbatools.io/Copy-SqlJobCategory

.EXAMPLE   
Copy-SqlJobCategory -Source sqlserver2014a -Destination sqlcluster

Copies all job categories from sqlserver2014a to sqlcluster, using Windows credentials. If job categories with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlJobCategory -Source sqlserver2014a -Destination sqlcluster -JobCategory PSJob -SourceSqlCredential $cred -Force

Copies a single job category, the PSJob job category from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster. If a job category with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-SqlJobCategory -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

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
	DynamicParam { if ($source) { return (Get-ParamSqlJobCategories -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	PROCESS
	{
		$jobcategories = $psboundparameters.JobCategories
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
		if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
		
		$serverjobcategories = $sourceserver.JobServer.JobCategories | Where-Object { $_.ID -ge 100 }
		$destjobcategories = $destserver.JobServer.JobCategories | Where-Object { $_.ID -ge 100 }
		
		foreach ($jobcategory in $serverjobcategories)
		{
			$categoryname = $jobcategory.name
			if ($jobcategories.length -gt 0 -and $jobcategories -notcontains $categoryname) { continue }
			
			if ($destjobcategories.name -contains $jobcategory.name)
			{
				if ($force -eq $false)
				{
					Write-Warning "Job category $categoryname exists at destination. Use -Force to drop and migrate."
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($destination, "Dropping job category $categoryname and recreating"))
					{
						try
						{
							Write-Verbose "Dropping Job category $categoryname"
							$destserver.jobserver.jobcategories[$jobcategory.name].Drop()
							Write-Output "Copying Job category $categoryname"
							$sql = $jobcategory.Script() | Out-String
							$sql = $sql -replace "'$source'", "'$destination'"
							Write-Verbose $sql
							$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
						}
						catch { Write-Exception $_ }
					}
				}
			}
			else
			{
				If ($Pscmdlet.ShouldProcess($destination, "Creating Job category $categoryname"))
				{
					try
					{
						Write-Output "Copying Job category $categoryname"
						$sql = $jobcategory.Script() | Out-String
						$sql = $sql -replace "'$source'", "'$destination'"
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
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Job category migration finished" }
	}
}