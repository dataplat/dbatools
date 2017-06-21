FUNCTION Get-DbaAgentJob {
	<#
		.SYNOPSIS
			Gets SQL Agent Job information for each instance(s) of SQL Server.

		.DESCRIPTION
			The Get-DbaAgentJob returns connected SMO object for SQL Agent Job information for each instance(s) of SQL Server.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
			to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Job
			The job(s) to process - this list is auto populated from the server. If unspecified, all jobs will be processed.

		.PARAMETER ExcludeJob
			The job(s) to exclude - this list is auto populated from the server.

		.PARAMETER Enabled
			True will return only enabled jobs, false will return disabled jobs.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

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

			Returns all SQL Agent Job on the local default SQL Server instance

		.EXAMPLE
			Get-DbaAgentJob -SqlInstance localhost, sql2016

			Returns all SQl Agent Job for the local and sql2016 SQL Server instances

		.EXAMPLE
			Get-DbaAgentJob -SqlInstance localhost -Enabled True

			Returns all enabled SQl Agent Job for the local SQL Server instances
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
		[ValidateSet('True', 'False')]
		[string]$Enabled,
		[switch]$Silent
	)

	process {
		foreach ($instance in $SqlInstance) {
			Write-Verbose "Attempting to connect to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Write-Warning "Can't connect to $instance or access denied. Skipping."
				continue
			}

			$jobs = $server.JobServer.Jobs
			if ($Enabled) {
				if($Enabled -eq 'True') { 
					$jobs = $Jobs | Where-Object IsEnabled -eq $true
				} else {
					$jobs = $Jobs | Where-Object IsEnabled -eq $false
				}
			}
			
			if ($Job) {
				$jobs = $jobs | Where-Object Name -In $Job
			}
			if ($ExcludeJob) {
				$jobs = $jobs | Where-Object Name -NotIn $ExcludeJob
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
