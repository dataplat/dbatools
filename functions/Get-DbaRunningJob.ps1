FUNCTION Get-DbaRunningJob
{
<#
.SYNOPSIS
Returns all non idle agent jobs running on the server.

.DESCRIPTION
This function returns agent jobs that active on the SQL Server intance when calling the command. The information is gathered the SMO JobServer.jobs and be returned either in detailed or standard format

.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to. This can be a
collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.PARAMETER Detailed
Returns more information about the running jobs than standard

.NOTES 
Original Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Get-DbaRunningJob

.EXAMPLE
Get-DbaRunningJob -SqlInstance localhost
Returns any active jobs on the localhost

.EXAMPLE
Get-DbaRunningJob -SqlInstance localhost -Detailed
Returns a detailed output of any active jobs on the localhost

.EXAMPLE
'localhost','localhost\namedinstance' | Get-DbaRunningJob
Returns all active jobs on multiple instances piped into the function

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[string[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$Detailed
	)
	BEGIN
	{
		$output = @()
	}
	PROCESS
	{
		FOREACH ($Server in $SqlInstance)
		{
			TRY
			{
				$server = Connect-SqlServer -SqlServer $server -SqlCredential $sqlcredential
			}
			CATCH
			{
				Write-Verbose "Failed to connect to: $Server"
				continue
			}
			
			$jobs = $server.JobServer.jobs | Where-Object { $_.CurrentRunStatus -ne 'Idle' }
			
			IF (!$jobs)
			{
				Write-Verbose "No Jobs are currently running on: $Server"
			}
			ELSE
			{
				foreach ($job in $jobs)
				{
					$output += [pscustomobject]@{
						ServerName = $Server.Name
						Name = $job.name
						Category = $job.Category
						CurrentRunStatus = $job.CurrentRunStatus
						CurrentRunStep = $job.CurrentRunStep
						HasSchedule = $job.HasSchedule
						LastRunDate = $job.LastRunDate
						LastRunOutcome = $job.LastRunOutcome
						JobStep = $job.JobSteps
					}
				}
			}
		}
	}
	END
	{
		IF ($Detailed -eq $true)
		{
			return $output | Sort-Object ServerName
		}
		ELSE
		{
			return ($output | Sort-Object ServerName | Select-Object ServerName, Name, Category, CurrentRunStatus, CurrentRunStep)
		}
	}
}
