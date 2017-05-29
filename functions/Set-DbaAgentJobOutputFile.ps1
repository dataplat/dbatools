function Set-DbaAgentJobOutputFile {
	<#
		.Synopsis


		.DESCRIPTION
			Sets the OutPut File for a step of an agent job with the Job Names and steps provided dynamically if required

		.PARAMETER SqlInstance
			The SQL Server that you're connecting to.

		.PARAMETER SQLCredential
			Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

		.PARAMETER JobName
			The Agent Job Name to provide Output File Path for. Also available dynamically

		.PARAMETER Step
			The Agent Job Step to provide Output File Path for. Also available dynamically

		.PARAMETER OutputFile
			The Full Path to the New Output file

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.NOTES
			Original Author - Rob Sewell (https://sqldbawithabeard.com)
			
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

			# todo - allow piping and add -All

		.EXAMPLE
			Set-DbaAgentJobOutputFile -SqlInstance SERVERNAME -JobName 'The Agent Job' -OutPutFile E:\Logs\AgentJobStepOutput.txt

			Sets the Job step for The Agent job on SERVERNAME to E:\Logs\AgentJobStepOutput.txt
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param
	(# The Server/instance
		[Parameter(Mandatory = $true, HelpMessage = 'The SQL Server Instance',
			ValueFromPipeline = $true,
			ValueFromPipelineByPropertyName = $true,
			ValueFromRemainingArguments = $false,
			Position = 0)]
		[ValidateNotNull()]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Parameter(Mandatory = $false, HelpMessage = 'SQL Credential',
			ValueFromPipeline = $true,
			ValueFromPipelineByPropertyName = $true,
			ValueFromRemainingArguments = $false)]
		[System.Management.Automation.PSCredential]$SqlCredential,
		[Parameter(Mandatory = $true, HelpMessage = 'The Full Output File Path',
			ValueFromPipeline = $true,
			ValueFromPipelineByPropertyName = $true,
			ValueFromRemainingArguments = $false)]
		[ValidateNotNull()]
		[ValidateNotNullOrEmpty()]
		[string]$OutputFile,
		[Parameter(Mandatory = $false, HelpMessage = 'The Job Step name',
			ValueFromPipeline = $true,
			ValueFromPipelineByPropertyName = $true)]
		[ValidateNotNull()]
		[ValidateNotNullOrEmpty()]
		[object[]]$Step
	)

	foreach ($instance in $sqlinstance) {
		try {
			$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
		}
		catch {
			Write-Warning "Failed to connect to: $instance"
			continue
		}

		if (!$JobName) {
			# This is because jobname isn't yet required
			Write-Warning "You must specify a jobname using -Jobs"
			return
		}

		foreach ($name in $JobName) {
			$Job = $server.JobServer.Jobs[$name]

			If ($step) {
				$steps = $Job.JobSteps | Where-Object Name -in $step

				if (!$steps) {
					Write-Warning "$step didn't return any steps"
					return
				}
			}
			else {
				if (($Job.JobSteps).Count -gt 1) {
					Write-output "Which Job Step do you wish to add output file to?"
					$steps = $Job.JobSteps | Out-GridView -Title "Choose the Job Steps to add an output file to" -PassThru -Verbose
				}
				else {
					$steps = $Job.JobSteps
				}
			}

			if (!$steps) {
				$steps = $Job.JobSteps
			}

			foreach ($jobstep in $steps) {
				$currentoutputfile = $jobstep.OutputFileName

				Write-Verbose "Current Output File for $job is $currentoutputfile"
				Write-Verbose "Adding $OutputFile to $jobstep for $Job"

				try {
					If ($Pscmdlet.ShouldProcess($jobstep, "Changing Output File from $currentoutputfile to $OutputFile")) {
						$jobstep.OutputFileName = $OutputFile
						$jobstep.Alter()
						$jobstep.Refresh()

						[pscustomobject]@{
							ComputerName   = $server.NetName
							InstanceName   = $server.ServiceName
							SqlInstance    = $server.DomainInstanceName
							Job            = $Job.Name
							JobStep        = $jobstep.Name
							OutputFileName = $currentoutputfile
						}
					}
				}
				catch {
					Write-Warning "Failed to add $OutputFile to $jobstep for $JobName"
				}
			}
		}
	}
}