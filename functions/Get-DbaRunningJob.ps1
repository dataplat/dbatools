FUNCTION Get-DbaRunningJob
{
<#
.SYNOPSIS
Returns all non idle agent jobs running on the server.

.DESCRIPTION
This function returns agent jobs that active on the SQL Server intance when calling the command. The information is gathered the SMO JobServer.jobs and be returned either in detailed or standard format

.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.PARAMETER Silent
Replaces user friendly yellow warnings with bloody red exceptions of doom!
Use this if you want the function to throw terminating errors you want to catch.

.NOTES 
Original Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

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
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential,
		[switch]$Silent
	)
	process
	{
		foreach ($instance in $SqlInstance)
		{
			try
			{
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Stop-Function -Message "Failed to connect to: $Server" -Target $server -ErrorRecord $_ -Continue
			}
			
			$jobs = $server.JobServer.jobs | Where-Object { $_.CurrentRunStatus -ne 'Idle' }
			
			IF (!$jobs)
			{
				Write-Message -Level Verbose -Message "No Jobs are currently running on: $Server"
			}
			else
			{
				foreach ($job in $jobs)
				{
					[pscustomobject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
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
}