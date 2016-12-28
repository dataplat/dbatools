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
	
.PARAMETER NoSchedule
Find all jobs with schedule set to it
	
.PARAMETER NoEmailNotification
Find all jobs without email notification configured

.PARAMETER Exclude
Allows you to enter an array of agent job names to ignore 

.PARAMETER Name
Filter agent jobs to only the names you list. Accepts wildcards (*).

.PARAMETER Category 
Filter based on agent job categories

.PARAMETER Owner
Filter based on owner of the job/s

.PARAMETER StepName
Filter based on StepName. Accepts wildcards (*).
	
.PARAMETER Detailed
Returns a more detailed output showing why each job has been reported

.NOTES 
Author: Stephen Bennett: https://sqlnotesfromtheunderground.wordpress.com/

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)

Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Find-DbaAgentJob

.EXAMPLE
Find-DbaAgentJob -SQLServer Dev01 -LastUsed 10 
Returns all agent job(s) that have not ran in 10 days

.EXAMPLE 
Find-DbaAgentJob -SQLServer Dev01 -Disabled -NoEmailNotification -NoSchedule -Detailed
Returns all agent job(s) that are either disabled, have no email notification or dont have a schedule. returned with detail

.EXAMPLE
Find-DbaAgentJob -SQLServer Dev01 -LastUsed 10 -Exclude "Yearly - RollUp Workload", "SMS - Notification" 
Returns all agent jobs that havent ran in the last 10 ignoring jobs "Yearly - RollUp Workload" and "SMS - Notification" 

.EXAMPLE 
Find-DbaAgentJob -SqlServer Dev01 -Category "REPL-Distribution", "REPL-Snapshot" -Detailed | ft -AutoSize -Wrap 
Returns all job/s on Dev01 that are in either category "REPL-Distribution" or "REPL-Snapshot" with detailed output

.EXAMPLE 
Get-SqlRegisteredServerName -SqlServer CMSServer -Group Production | Find-DbaAgentJob -Disabled -NoSchedule -Detailed | ft -AutoSize -Wrap
Queries CMS server to return all SQL instances in the Production folder and then list out all agent jobs that have either been disabled or have no schedule. 

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[int]$LastUsed,
		[switch]$Disabled,
		[switch]$NoSchedule,
		[switch]$NoEmailNotification,
		[string[]]$Category,
		[string]$Owner,
		[string[]]$Exclude,
		[string[]]$Name,
		[string[]]$StepName,
		[switch]$Detailed
	)
	BEGIN
	{
		$output = @()
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
			
			if ($Name)
			{
				foreach ($jobname in $Name)
				{
					Write-Verbose "Gettin some jobs by their names"
					$output += $jobs | Where-Object { $_.Name -like $jobname }
				}
			}
			
			if ($StepName)
			{
				foreach ($name in $StepName)
				{
					Write-Verbose "Gettin some jobs by their names"
					$output += $jobs | Where-Object { $_.JobSteps.Name -like $name }
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
		}
		
		if ($Detailed -eq $true)
		{
			return ($output | Select-Object @{ Name = "ServerName"; Expression = { $_.Parent.name } }, name, LastRunDate, IsEnabled, HasSchedule, OperatorToEmail, Category, OwnerLoginName -Unique)
		}
		else
		{
			return ($output | Select-Object @{ Name = "ServerName"; Expression = { $_.Parent.name } }, name -Unique)
		}
	}
}