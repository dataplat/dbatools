FUNCTION Find-DbaAgentJob
{
<#
.SYNOPSIS 
Find-DbaAgentJob finds agent job/s that fit certain search filters.

.DESCRIPTION
This command filters SQL Agent jobs giving the DBA a list of jobs that may need attention or could possibly be options for removal.
	
.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER LastUsed
Find all jobs that havent ran in the INT number of previous day(s)

.PARAMETER Disabled
Find all jobs that are disabled

.PARAMETER Failed
Find all jobs that have failed

.PARAMETER NoSchedule
Find all jobs with schedule set to it
	
.PARAMETER NoEmailNotification
Find all jobs without email notification configured

.PARAMETER Exclude
Allows you to enter an array of agent job names to ignore 

.PARAMETER Name
Filter agent jobs to only the names you list. This is a regex pattern by default so no asterisks are necessary. If you need an exact match, use -Exact.

.PARAMETER Category 
Filter based on agent job categories

.PARAMETER Owner
Filter based on owner of the job/s

.PARAMETER StepName
Filter based on StepName. This is a regex pattern by default so no asterisks are necessary. If you need an exact match, use -Exact.

.PARAMETER Exact
Job Names and Step Names are searched for by regex by default. Use Exact to return only exact matches.
	
.PARAMETER Since
Datetime object used to narrow the results to a date
	
.NOTES
Tags: DisasterRecovery, Backup
Author: Stephen Bennett: https://sqlnotesfromtheunderground.wordpress.com/

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Find-DbaAgentJob

.EXAMPLE
Find-DbaAgentJob -SQLServer Dev01 -Name backup 
Returns all agent job(s) that have backup in the name
	
.EXAMPLE
Find-DbaAgentJob -SQLServer Dev01 -LastUsed 10 
Returns all agent job(s) that have not ran in 10 days

.EXAMPLE 
Find-DbaAgentJob -SQLServer Dev01 -Disabled -NoEmailNotification -NoSchedule
Returns all agent job(s) that are either disabled, have no email notification or dont have a schedule. returned with detail

.EXAMPLE
Find-DbaAgentJob -SQLServer Dev01 -LastUsed 10 -Exclude "Yearly - RollUp Workload", "SMS - Notification" 
Returns all agent jobs that havent ran in the last 10 ignoring jobs "Yearly - RollUp Workload" and "SMS - Notification" 

.EXAMPLE 
Find-DbaAgentJob -SqlServer Dev01 -Category "REPL-Distribution", "REPL-Snapshot" -Detailed | Format-Table -AutoSize -Wrap 
Returns all job/s on Dev01 that are in either category "REPL-Distribution" or "REPL-Snapshot" with detailed output

.EXAMPLE
Find-DbaAgentJob -SQLServer Dev01, Dev02 -Failed -Since '7/1/2016 10:47:00'
Returns all agent job(s) that have failed since July of 2016 (and still have history in msdb)
	
.EXAMPLE 
Get-SqlRegisteredServerName -SqlServer CMSServer -Group Production | Find-DbaAgentJob -Disabled -NoSchedule -Detailed | Format-Table -AutoSize -Wrap
Queries CMS server to return all SQL instances in the Production folder and then list out all agent jobs that have either been disabled or have no schedule. 

.EXAMPLE
Find-DbaAgentJob -SQLServer Dev01, Dev02 -Name Mybackup -Exact 
Returns all agent job(s) that are named exactly Mybackup
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string[]]$Name,
		[string[]]$StepName,
		[switch]$Exact,
		[int]$LastUsed,
		[switch]$Disabled,
		[switch]$Failed,
		[switch]$NoSchedule,
		[switch]$NoEmailNotification,
		[string[]]$Category,
		[string]$Owner,
		[string[]]$Exclude,
		[datetime]$Since
	)
	begin
	{
		if ($Failed, [boolean]$Name, [boolean]$StepName, $LastUsed, $Disabled, $NoSchedule, $NoEmailNotification, [boolean]$Category, [boolean]$Owner, [boolean]$Exclude -notcontains $true)
		{
			Write-Warning "At least one search term must be specified"
			continue
		}
	}
	PROCESS
	{
		foreach ($servername in $SqlServer)
		{
			Write-Verbose "Running Scan on: $servername"
			
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Verbose "Failed to connect to: $servername"
				continue
			}
			
			$jobs = $server.JobServer.jobs
			$output = @()
			
			if ($Failed)
			{
				Write-Verbose "Checking for failed jobs"
				$output += $jobs | Where-Object { $_.LastRunOutcome -ne "Success" }
			}
			
			if ($Name)
			{
				foreach ($jobname in $Name)
				{
					Write-Verbose "Gettin some jobs by their names"
					if ($Exact -eq $true)
					{
						$output += $jobs | Where-Object { $_.Name -eq $name }
					}
					else
					{
						try
						{
							$output += $jobs | Where-Object { $_.Name -match $name }
						}
						catch
						{
							# they prolly put aterisks thinking it's a like
							$Name = $Name -replace '\*', ''
							$Name = $Name -replace '\%', ''
							$output += $jobs | Where-Object { $_.Name -match $name }
						}
					}
				}
			}
			
			if ($StepName)
			{
				foreach ($name in $StepName)
				{
					Write-Verbose "Gettin some jobs by their names"
					if ($Exact -eq $true)
					{
						$output += $jobs | Where-Object { $_.JobSteps.Name -eq $name }
					}
					else
					{
						try
						{
							$output += $jobs | Where-Object { $_.JobSteps.Name -match $name }
						}
						catch
						{
							# they prolly put aterisks thinking it's a like
							$StepName = $StepName -replace '\*', ''
							$StepName = $StepName -replace '\%', ''
							$output += $jobs | Where-Object { $_.JobSteps.Name -match $name }
						}
					}
				}
			}
			
			if ($LastUsed)
			{
				$Since = $LastUsed * -1
				$SinceDate = (Get-date).AddDays($Since)
				Write-Verbose "Finding job/s not ran in last $Since days"
				$output += $jobs | Where-Object { $_.LastRunDate -le $SinceDate }
			}
			
			if ($Disabled -eq $true)
			{
				Write-Verbose "Finding job/s that are disabled"
				$output += $jobs | Where-Object { $_.IsEnabled -eq $false }
			}
			
			if ($NoSchedule -eq $true)
			{
				Write-Verbose "Finding job/s that have no schedule defined"
				$output += $jobs | Where-Object { $_.HasSchedule -eq $false }
			}
			if ($NoEmailNotification -eq $true)
			{
				Write-Verbose "Finding job/s that have no email operator defined"
				$output += $jobs | Where-Object { $_.OperatorToEmail -eq "" }
			}
			
			if ($Category)
			{
				Write-Verbose "Finding job/s that have no email operator defined"
				$output += $jobs | Where-Object { $Category -contains $_.Category }
			}
			
			if ($Owner)
			{
				Write-Verbose "Finding job/s with owner critera"
				if ($Owner -match "-")
				{
					$OwnerMatch = $Owner -replace "-", ""
					Write-Verbose "Checking for jobs that NOT owned by: $OwnerMatch"
					$output += $server.JobServer.jobs | Where-Object { $OwnerMatch -notcontains $_.OwnerLoginName }
				}
				else
				{
					Write-Verbose "Checking for jobs that are owned by: $owner"
					$output += $server.JobServer.jobs | Where-Object { $Owner -contains $_.OwnerLoginName }
				}
			}
			
			if ($Exclude)
			{
				Write-Verbose "Excluding job/s based on Exclude"
				$output = $output | Where-Object { $Exclude -notcontains $_.Name }
			}
			
			if ($Since)
			{
				#$Since = $Since.ToString("yyyy-MM-dd HH:mm:ss")
				Write-Verbose "Getting only jobs whose LastRunDate is greater than or equal to $since"
				$output = $output | Where-Object { $_.LastRunDate -ge $since }
			}
			
			$jobs = $output | Select-Object -Unique
			
			foreach ($job in $jobs)
			{
				[PSCustomObject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlInstance = $server.Name
					Name = $job.Name
					LastRunDate = $job.LastRunDate
					IsEnabled = $job.IsEnabled
					CreateDate = $job.CreateDate
					HasSchedule = $job.HasSchedule
					OperatorToEmail = $job.OperatorToEmail
					Category = $job.Category
					OwnerLoginName = $job.OwnerLoginName
					Job = $job
				} | Select-DefaultView -ExcludeProperty Job
			}
		}
	}
}
