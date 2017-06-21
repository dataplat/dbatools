FUNCTION Get-DbaAgentJobHistory {
	<#
		.SYNOPSIS
			Gets execution history of SQL Agent Job on instance(s) of SQL Server.

		.DESCRIPTION
			Get-DbaAgentJobHistory returns all information on the executions still available on each instance(s) of SQL Server submitted.
            The cleanup of SQL Agent history determines how many records are kept.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
			to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Job
			The job(s) to process - this list is auto populated from the server. If unspecified, all jobs will be processed.

		.PARAMETER ExcludeJob
			The job(s) to exclude - this list is auto populated from the server.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Job, Agent
			Original Author: Klaas Vandenberghe ( @PowerDbaKlaas )

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaAgentJobHistory

		.EXAMPLE
			Get-DbaAgentJobHistory -SqlInstance localhost

			Returns all SQL Agent Job on the local default SQL Server instance

		.EXAMPLE
			Get-DbaAgentJobHistory -SqlInstance localhost, sql2016

			Returns all SQl Agent Job for the local and sql2016 SQL Server instances

		.EXAMPLE
			'sql1','sql2\Inst2K17' | Get-DbaAgentJobHistory

			Returns all SQl Agent Job for sql1 and sql2\Inst2K17
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
<#
https://msdn.microsoft.com/en-us/library/ms201680.aspx
https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.agent.jobhistoryfilter(v=sql.120).aspx
#>
#ipmo sqlserver
$serv = New-Object Microsoft.SqlServer.Management.Smo.Server SQLDev02
$DateFrom = (Get-Date).AddDays(-2)
$Filter = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobHistoryFilter;
$Filter.StartRunDate = $DateFrom;

$serv.JobServer.EnumJobHistory($Filter) |
foreach {
				Add-Member -InputObject $_ -MemberType NoteProperty -Name ComputerName -value $serv.NetName
				Add-Member -InputObject $_ -MemberType NoteProperty -Name InstanceName -value $serv.ServiceName
				Add-Member -InputObject $_ -MemberType NoteProperty -Name SqlInstance -value $serv.DomainInstanceName

			#	Select-DefaultView -InputObject $_ -Property ComputerName, InstanceName, SqlInstance, JobName, StepName, RunDate, RunDuration, RunStatus
            #$_
			} #foreach jobhistory
} #foreach instance
} # process
} #function