Function Set-DbaAgentJobOutputFile
{
<#
.Synopsis
   Sets the OutPut File for a step of an agent job with the Job Names and steps provided dynamically 
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
	
.EXAMPLE
   Set-DbaAgentJobOutputFile -sqlserver SERVERNAME -JobName 'The Agent Job' -OutPutFile E:\Logs\AgentJobStepOutput.txt

   Sets the Job step for The Agent job on SERVERNAME to E:\Logs\AgentJobStepOutput.txt
.NOTES
   AUTHOR - Rob Sewell https://sqldbawithabeard.com
   DATE - 30/10/2016

    dbatools PowerShell module (https://dbatools.io)
    Copyright (C) 2016 Chrissy LeMaire
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.
	
	# todo - allow piping and add -All
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
		[object[]]$SqlInstance,
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
		[object[]]$Step)
	
	DynamicParam { if ($sqlinstance) { return (Get-ParamSqlJobs -SqlServer $sqlinstance[0] -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		$JobName = $psboundparameters.Jobs
	}
	PROCESS
	{
		foreach ($instance in $sqlinstance)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to: $instance"
				continue
			}
			
			if (!$JobName)
			{
				# This is because jobname isn't yet required
				Write-Warning "You must specify a jobname using -Jobs"
				return
			}
			
			foreach ($name in $JobName)
			{
				$Job = $server.JobServer.Jobs[$name]
				
				If ($step)
				{
					$steps = $Job.JobSteps | Where-Object Name -in $step
					
					if (!$steps)
					{
						Write-Warning "$step didn't return any steps"
						return
					}
				}
				else
				{
					if (($Job.JobSteps).Count -gt 1)
					{
						Write-output "Which Job Step do you wish to add output file to?"
						$steps = $Job.JobSteps | Out-GridView -Title "Choose the Job Steps to add an output file to" -PassThru -Verbose
					}
					else
					{
						$steps = $Job.JobSteps
					}
				}
				
				if (!$steps)
				{
					$steps = $Job.JobSteps
				}
				
				foreach ($jobstep in $steps)
				{
					$currentoutputfile = $jobstep.OutputFileName
					
					Write-Verbose "Current Output File for $job is $currentoutputfile"
					Write-Verbose "Adding $OutputFile to $jobstep for $Job"
					
					try
					{
						If ($Pscmdlet.ShouldProcess($jobstep, "Changing Output File from $currentoutputfile to $OutputFile"))
						{
							$jobstep.OutputFileName = $OutputFile
							$jobstep.Alter()
							$jobstep.Refresh()
							
							[pscustomobject]@{
								ComputerName = $server.NetName
								InstanceName = $server.ServiceName
								SqlInstance = $server.DomainInstanceName
								Job = $Job.Name
								JobStep = $jobstep.Name
								OutputFileName = $currentoutputfile
							}
						}
					}
					catch
					{
						Write-Warning "Failed to add $OutputFile to $jobstep for $JobName"
					}
				}
			}
		}
	}
}