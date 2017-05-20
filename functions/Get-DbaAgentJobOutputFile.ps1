Function Get-DbaAgentJobOutputFile
{
<#
.Synopsis
   Returns the Output File for each step of one or many agent job with the Job Names provided dynamically if 
   required for one or more SQL Instances

.DESCRIPTION
   This function returns for one or more SQL Instances the output file value for each step of one or many agent job with the Job Names 
   provided dynamically. It will not return anything if there is no Output File

.PARAMETER SqlInstance 
    The SQL Server that you're connecting to. Or an array of SQL Servers

.PARAMETER SQLCredential
    Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by 
    the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it 
    contains a backslash.

.PARAMETER JobName
    The Agent Job Name to provide Output File Path for. Also available dynamically. If ommitted all Agent Jobs will be used

.EXAMPLE
   Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME -Job 'The Agent Job' 

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVERNAME instance  

.EXAMPLE
   Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME 

   This will return the paths to the output files for each of the job step of all the Agent Jobs
   on the SERVERNAME instance   

.EXAMPLE
   Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME,SERVERNAME2 -Job 'The Agent Job'

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVERNAME instance and SERVERNAME2

.EXAMPLE
   $Servers = 'SERVER','SERVER\INSTANCE1'
   Get-DbaAgentJobOutputFile -SqlInstance $Servers -Job 'The Agent Job' -OpenFile 

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVER instance and the SERVER\INSTANCE1 and open the files if they are available

.EXAMPLE 
   Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME  | Out-GridView

   This will return the paths to the output files for each of the job step of all the Agent Jobs
   on the SERVERNAME instance and Pipe them to Out-GridView

.EXAMPLE 
   (Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME | ogv -PassThru).FileName | Invoke-Item

   This will return the paths to the output files for each of the job step of all the Agent Jobs
   on the SERVERNAME instance and Pipe them to Out-GridView and enable you to choose the output
   file and open it
   
.EXAMPLE 
   Get-DbaAgentJobOutputFile -SqlInstance SERVERNAME -Verbose

   This will return the paths to the output files for each of the job step of all the Agent Jobs
   on the SERVERNAME instance and also show the job steps without an output file

.NOTES
   AUTHOR - Rob Sewell https://sqldbawithabeard.com
   DATE - 30/10/2016

    dbatools PowerShell module (https://dbatools.io)
    Copyright (C) 2016 Chrissy LeMaire
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

#>
	[CmdletBinding()]
	param
	(
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
				   ValueFromPipelineByPropertyName = $true,
				   ValueFromRemainingArguments = $false,
				   Position = 1)]
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	

	
	BEGIN
	{
		$jobname = $psboundparameters.Jobs
	}
	PROCESS
	{
		foreach ($instance in $sqlinstance)
		{
			try
			{
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to: $instance"
				continue
			}
			
			$jobs = $Server.JobServer.Jobs
			
			if ($JobName)
			{
				$jobs = @()
				
				foreach ($name in $jobname)
				{
					$jobs += $server.JobServer.Jobs[$name]
				}
			}
			else
			{
				$jobs = $server.JobServer.Jobs
			}
			
			foreach ($Job in $Jobs)
			{
				foreach ($Step in $Job.JobSteps)
				{
					if ($Step.OutputFileName)
					{
						[pscustomobject]@{
							ComputerName = $server.NetName
							InstanceName = $server.ServiceName
							SqlInstance = $server.DomainInstanceName
							Job = $Job.Name
							JobStep = $step.Name
							OutputFileName = $Step.OutputFileName
							RemoteOutputFileName = Join-AdminUNC $Server.ComputerNamePhysicalNetBIOS $Step.OutputFileName
						}
					}
					else
					{
						Write-Verbose "$step for $job has no output file"
					}
				}
			}
		}
	}
}