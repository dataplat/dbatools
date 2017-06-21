FUNCTION Get-DbaAgentJobHistory {
	<#
		.SYNOPSIS
			Gets execution history of SQL Agent Job on instance(s) of SQL Server.

		.DESCRIPTION
			Get-DbaAgentJobHistory returns all information on the executions still available on each instance(s) of SQL Server submitted.
            The cleanup of SQL Agent history determines how many records are kept.

            https://msdn.microsoft.com/en-us/library/ms201680.aspx
            https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.agent.jobhistoryfilter(v=sql.120).aspx

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
			to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER JobName
			The name of the job from which the history is wanted. If unspecified, all jobs will be processed.

		.PARAMETER StartDate
			The DateTime starting from which the history is wanted. If unspecified, all available records will be processed.

		.PARAMETER EndDate
			The DateTime before which the history is wanted. If unspecified, all available records will be processed.

		.PARAMETER NoJobSteps
			Use this switch to discard all job steps, and return only the job totals

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

			Returns all SQL Agent Job execution results on the local default SQL Server instance.

		.EXAMPLE
			Get-DbaAgentJobHistory -SqlInstance localhost, sql2016

			Returns all SQL Agent Job execution results for the local and sql2016 SQL Server instances.

		.EXAMPLE
			'sql1','sql2\Inst2K17' | Get-DbaAgentJobHistory

			Returns all SQL Agent Job execution results for sql1 and sql2\Inst2K17.

		.EXAMPLE
			Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 | select *

			Returns all properties for all SQl Agent Job execution results on sql2\Inst2K17.

		.EXAMPLE
			Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -NoJobSteps

			Returns the SQL Agent Job execution results for the whole jobs on sql2\Inst2K17, leaving out job step execution results.

		.EXAMPLE
			Get-DbaAgentJobHistory -SqlInstance sql2\Inst2K17 -StartDate '2017-05-22' -EndDate '2017-05-23 12:30:00'

			Returns the SQL Agent Job execution results between 2017/05/22 00:00:00 and 2017/05/23 12:30:00 on sql2\Inst2K17.
	#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[string]$JobName,
		[DateTime]$StartDate = '1900-01-01',
		[DateTime]$EndDate = $(Get-Date),
        [Switch]$NoJobSteps,
		[switch]$Silent
	)
    begin {
    
        $Filter = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobHistoryFilter
        $Filter.StartRunDate = $StartDate
        $Filter.EndRunDate = $EndDate
        if ( $JobName ) { $Filter.JobName = $JobName }
    }
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Message "Attempting to connect to $instance" -Level Verbose
			try {
				$Server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Could not connect to Sql Server instance $instance" -Target $instance -Continue
			}
            try {
			Write-Message -Message "Attempting to get job history from $instance" -Level Verbose
            $Executions = $server.JobServer.EnumJobHistory($Filter)
            if ( $NoJobSteps ) {
                $Executions = $Executions | Where-Object { $_.StepID -eq 0 }
            }
            foreach ( $Execution in $Executions ) {
                Add-Member -InputObject $Execution -MemberType NoteProperty -Name ComputerName -value $server.NetName
                Add-Member -InputObject $Execution -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -InputObject $Execution -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                Select-DefaultView -InputObject $Execution -Property ComputerName, InstanceName, SqlInstance, JobName, StepName, RunDate, RunDuration, RunStatus
                } #foreach jobhistory
            }
			catch {
				Stop-Function -Message "Could not get Agent Job History from $instance" -Target $instance -Continue
			}
        } #foreach instance
    } # process
} #function