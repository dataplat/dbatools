Function Get-DbaJobOutputFile
{
<#
.Synopsis
   Returns the Output File for each step of one or many agent job with the Job Names provided dynamically if 
   required for one or more SQL Instances
.DESCRIPTION
   This function returns for one or more SQL Instances the output file value for each step of one or many agent job with the Job Names 
   provided dynamically if required

.PARAMETER SqlServer 
    The SQL Server that you're connecting to. Or an array of SQL Servers

.PARAMETER SQLCredential
    Credential object used to connect to the SQL Server as a different user be it Windows or SQL Server. Windows users are determiend by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

.PARAMETER JobName
    The Agent Job Name to provide Output File Path for. Also available dynamically. If ommitted all Agent Jobs will be used

.EXAMPLE
   Get-DbaJobOutputFile -SqlServer SERVERNAME -Jobs 'The Agent Job' 

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVERNAME instance  

.EXAMPLE
   Get-DbaJobOutputFile -SqlServer SERVERNAME 

   This will return the paths to the output files for each of the job step of all the Agent Jobs
   on the SERVERNAME instance   

.EXAMPLE
   Get-DbaJobOutputFile -SqlServer SERVERNAME,SERVERNAME2 -Jobs 'The Agent Job'

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVERNAME instance and SERVERNAME2

.EXAMPLE
   $Servers = 'SERVER','SERVER\INSTANCE1'
   Get-DbaJobOutputFile -SqlServer $Servers -Jobs 'The Agent Job' -OpenFile 

   This will return the paths to the output files for each of the job step of the The Agent Job Job 
   on the SERVER instance and the SERVER\INSTANCE1 and open the files if they are available

.EXAMPLE 
   Get-DbaJobOutputFile -SqlServer SERVERNAME  | Out-GridView

   This will return the paths to the output files for each of the job step of all the Agent Jobs
   on the SERVERNAME instance and Pipe them to Out-GridView

.EXAMPLE 
   (Get-DbaJobOutputFile -SqlServer SERVERNAME | ogv -PassThru).FileName | Invoke-Item

   This will return the paths to the output files for each of the job step of all the Agent Jobs
   on the SERVERNAME instance and Pipe them to Out-GridView and enable you to choose the output
   file and open it

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
(# The Server/instance 
        [Parameter(Mandatory=$true,HelpMessage='The SQL Server Instance', 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   Position=0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [object]$SqlServer,
        [Parameter(Mandatory=$false,HelpMessage='SQL Credential', 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   Position=1)]
        [System.Management.Automation.PSCredential]$SqlCredential
)
    DynamicParam { if ($SqlServer) { return (Get-ParamSqlJobs -SqlServer $SqlServer -SqlCredential $SourceSqlCredential) } }

	BEGIN 
    {
		$jobname = $psboundparameters.Jobs   
    }
    PROCESS
    {
        foreach ($instance in $sqlserver)
        {
            $Server = Connect-SqlServer -SqlServer $instance  -SqlCredential $SqlCredential
            $jobs = $Server.JobServer.Jobs
            if ($JobName)
            {
                $Job = $server.JobServer.Jobs[$JobName]
            }
            else
            {
                foreach($Job in $Jobs)
                {
                foreach($Step in $Job.JobSteps)
                {
                    if($Step.OutputFileName)
                    {
                        $fileName = Join-AdminUNC $Server.ComputerNamePhysicalNetBIOS $Step.OutputFileName
                    }
                    else
                    {
                        $fileName = 'No Output File'
                    }
                    [pscustomobject]@{
                    ComputerName = $Server.ComputerNamePhysicalNetBIOS
                    InstanceName = $Server.Instancename
                    SqlInstance = $Server.Name
                    Job = $Job.Name
                    JobStep = $step.Name
                    FileName = $FileName
                    }
                }
            }
            else
            {
                foreach($Job in $Jobs)
                {
                    foreach($Step in $Job.JobSteps)
                    {
                        if($Step.OutputFileName)
                        {
                            $fileName = Join-AdminUNC $Server.ComputerNamePhysicalNetBIOS $Step.OutputFileName
                        }
                        else
                        {
                            $fileName = 'No Output File'
                        }
                        [pscustomobject]@{
                        ComputerName = $Server.ComputerNamePhysicalNetBIOS
                        InstanceName = $Server.Instancename
                        SqlInstance = $Server.Name
                        Job = $Job.Name
                        JobStep = $step.Name
                        FileName = $FileName
                        }
                    }
                }
            }             
            $server.ConnectionContext.Disconnect()
        }
    }
    END
    {

    }
}

