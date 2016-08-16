Function Copy-SqlJob
{
<#
.SYNOPSIS
Copy-SqlJob migrates jobs from one SQL Server to another.

.DESCRIPTION
By default, all jobs are copied. The -Jobs parameter is autopopulated for command-line completion and can be used to copy only specific jobs.

If the job already exists on the destination, it will be skipped unless -Force is used.

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

.PARAMETER DisableOnSource
Disable the job on the source server

.PARAMETER DisableOnDestination
Disable the newly migrated job on the destination server

.NOTES
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlJob

.EXAMPLE
Copy-SqlJob -Source sqlserver2014a -Destination sqlcluster

Copies all jobs from sqlserver2014a to sqlcluster, using Windows credentials. If jobs with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE
Copy-SqlJob -Source sqlserver2014a -Destination sqlcluster -Job PSJob -SourceSqlCredential $cred -Force

Copies a single job, the PSJob job from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a job with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE
Copy-SqlJob -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

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
		[switch]$DisableOnSource,
		[switch]$DisableOnDestination,
		[switch]$Force
	)
	DynamicParam { if ($source) { return (Get-ParamSqlJobs -SqlServer $Source -SqlCredential $SourceSqlCredential) } }

	BEGIN {
		$jobs = $psboundparameters.Jobs
		$exclude = $psboundparameters.Exclude

		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName

	}
	PROCESS
	{

		$serverjobs = $sourceserver.JobServer.Jobs
		$destjobs = $destserver.JobServer.Jobs

		foreach ($job in $serverjobs)
		{
			$jobname = $job.name

			if ($jobs.count -gt 0 -and $jobs -notcontains $jobname -or $exclude -contains $jobname) { continue }

			$dbnames = $job.JobSteps.Databasename | Where-Object { $_.length -gt 0 }
			$missingdb = $dbnames | Where-Object { $destserver.Databases.Name -notcontains $_ }

			if ($missingdb.count -gt 0 -and $dbnames.count -gt 0)
			{
				$missingdb = ($missingdb | Sort-Object | Get-Unique) -join ", "
				Write-Warning "[Job: $jobname] Database(s) $missingdb doesn't exist on destination. Skipping."
				continue
			}

			$missinglogin = $job.OwnerLoginName | Where-Object { $destserver.Logins.Name -notcontains $_ }

			if ($missinglogin.count -gt 0)
			{
				$missinglogin = ($missinglogin | Sort-Object | Get-Unique) -join ", "
				Write-Warning "[Job: $jobname] Login(s) $missinglogin doesn't exist on destination. Skipping."
				continue
			}

			$proxynames = $job.JobSteps.ProxyName | Where-Object { $_.length -gt 0 }
			$missingproxy = $proxynames | Where-Object { $destserver.JobServer.ProxyAccounts.Name -notcontains $_ }

			if ($missingproxy.count -gt 0 -and $proxynames.count -gt 0)
			{
				$missingproxy = ($missingproxy | Sort-Object | Get-Unique) -join ", "
				Write-Warning "[Job: $jobname] Proxy Account(s) $($proxynames[0]) doesn't exist on destination. Skipping."
				continue
			}

			if ($destjobs.name -contains $job.name)
			{
				if ($force -eq $false)
				{
					Write-Warning "[Job: $jobname] Job $jobname exists at destination. Use -Force to drop and migrate."
					continue
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($destination, "Dropping job $jobname and recreating"))
					{
						try
						{
							Write-Verbose "Dropping Job $jobname"
							$destserver.JobServer.Jobs[$job.name].Drop()
						}
						catch
						{
							Write-Exception $_
							continue
						}
					}
				}
			}

			If ($Pscmdlet.ShouldProcess($destination, "Creating Job $jobname"))
			{
				try
				{
					Write-Output "Copying Job $jobname"
					$sql = $job.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					Write-Verbose $sql
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch
				{
					Write-Exception $_
					continue
				}
			}
			
			if ($DisableOnDestination)
			{
                If ($Pscmdlet.ShouldProcess($destination, "Disabling $jobname"))
			    {
					Write-Output "Disabling $jobname on $destination"
					$destserver.JobServer.Jobs.Refresh()
					$destserver.JobServer.Jobs[$job.name].IsEnabled = $False
					$destserver.JobServer.Jobs[$job.name].Alter()
				}
            }

			if ($DisableOnSource)
			{
                If ($Pscmdlet.ShouldProcess($source, "Disabling $jobname"))
			    {
					Write-Output "Disabling $jobname on $source"
					$job.IsEnabled = $false
					$job.Alter()
				}
			}
		}
	}

	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Job migration finished" }
	}
}