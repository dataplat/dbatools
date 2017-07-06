FUNCTION Get-DbaAgentJob {
	<#
		.SYNOPSIS
			Gets SQL Agent Job information for each instance(s) of SQL Server.

		.DESCRIPTION
			The Get-DbaAgentJob returns connected SMO object for SQL Agent Job information for each instance(s) of SQL Server.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Job
			The job(s) to process - this list is auto-populated from the server. If unspecified, all jobs will be processed.

		.PARAMETER ExcludeJob
			The job(s) to exclude - this list is auto-populated from the server.

		.PARAMETER NoDisabledJobs
			Switch will exclude disabled jobs from the output.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages.

		.NOTES
			Tags: Job, Agent
			Original Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaAgentJob

		.EXAMPLE
			Get-DbaAgentJob -SqlInstance localhost

			Returns all SQL Agent Jobs on the local default SQL Server instance

		.EXAMPLE
			Get-DbaAgentJob -SqlInstance localhost, sql2016

			Returns all SQl Agent Jobs for the local and sql2016 SQL Server instances

		.EXAMPLE
			Get-DbaAgentJob -SqlInstance localhost -Job BackupData, BackupDiff

			Returns all SQL Agent Jobs named BackupData and BackupDiff from the local SQL Server instance.

		.EXAMPLE
			Get-DbaAgentJob -SqlInstance localhost -ExcludeJob BackupDiff

			Returns all SQl Agent Jobs for the local SQL Server instances, except the BackupDiff Job.
			
		.EXAMPLE
			Get-DbaAgentJob -SqlInstance localhost -NoDisabledJobs

			Returns all SQl Agent Jobs for the local SQL Server instances, excluding the disabled jobs.
	#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[object[]]$Job,
		[object[]]$ExcludeJob,
		[switch]$NoDisabledJobs,
		[switch]$Silent
	)

	process {
		foreach ($instance in $SqlInstance) {
			Write-Verbose "Attempting to connect to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			$jobs = $server.JobServer.Jobs
			
			if ($Job) {
				$jobs = $jobs | Where-Object Name -In $Job
			}
			if ($ExcludeJob) {
				$jobs = $jobs | Where-Object Name -NotIn $ExcludeJob
			}
			if ($NoDisabledJobs) {
				$jobs = $Jobs | Where-Object IsEnabled -eq $true
			}
			
			foreach ($agentJob in $jobs) {
				Add-Member -InputObject $agentJob -MemberType NoteProperty -Name ComputerName -value $agentJob.Parent.Parent.NetName
				Add-Member -InputObject $agentJob -MemberType NoteProperty -Name InstanceName -value $agentJob.Parent.Parent.ServiceName
				Add-Member -InputObject $agentJob -MemberType NoteProperty -Name SqlInstance -value $agentJob.Parent.Parent.DomainInstanceName	
			
				Select-DefaultView -InputObject $agentJob -Property ComputerName, InstanceName, SqlInstance, Name, Category, OwnerLoginName, 'IsEnabled as Enabled', LastRunDate, DateCreated, HasSchedule, OperatorToEmail
			}
		}
	}
}
