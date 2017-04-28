function Set-DbaAgentJobStep {
    <#
.SYNOPSIS 
Set-DbaAgentJobStep updates a job step.

.DESCRIPTION
Set-DbaAgentJobStep updates a job step in the SQL Server Agent with parameters supplied.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER JobName
The name of the job. Can be null if the the job id is being used.

.PARAMETER StepName
The name of the step.

.PARAMETER NewName
The new name for the step in case it needs to be renamed.

.PARAMETER SubSystem
The subsystem used by the SQL Server Agent service to execute command.
Allowed values 'ActiveScripting','AnalysisCommand','AnalysisQuery','CmdExec','Distribution','LogReader','Merge','PowerShell','QueueReader','Snapshot','Ssis','TransactSql'

.PARAMETER Command
The commands to be executed by SQLServerAgent service through subsystem.

.PARAMETER CmdExecSuccessCode 
The value returned by a CmdExec subsystem command to indicate that command executed successfully.

.PARAMETER OnSuccessAction 
The action to perform if the step succeeds.
Allowed values  "QuitWithSuccess" (default), "QuitWithFailure", "GoToNextStep", "GoToStep".
The text value van either be lowercase, uppercase or something in between as long as the text is correct.

.PARAMETER OnSuccessStepId 
The ID of the step in this job to execute if the step succeeds and OnSuccessAction is "GoToNextStep".

.PARAMETER OnFailAction 
The action to perform if the step fails.
Allowed values  "QuitWithSuccess" (default), "QuitWithFailure", "GoToNextStep", "GoToStep".
The text value van either be lowercase, uppercase or something in between as long as the text is correct.

.PARAMETER OnFailStepId 
The ID of the step in this job to execute if the step fails and OnFailAction is "GoToNextStep".

.PARAMETER DatabaseName
The name of the database in which to execute a Transact-SQL step. The default is 'master'.

.PARAMETER DatabaseUserName 
The name of the user account to use when executing a Transact-SQL step. The default is 'sa'.

.PARAMETER RetryAttempts
The number of retry attempts to use if this step fails. The default is 0.

.PARAMETER RetryInterval
The amount of time in minutes between retry attempts. The default is 0.

.PARAMETER OutputFileName
The name of the file in which the output of this step is saved.

.PARAMETER Flag
Sets the flag(s) for the job step.

Flag                                    Description
----------------------------------------------------------------------------
AppendAllCmdExecOutputToJobHistory      Job history, including command output, is appended to the job history file.
AppendToJobHistory                      Job history is appended to the job history file.
AppendToLogFile                         Job history is appended to the SQL Server log file.
AppendToTableLog                        Job history is appended to a log table.
LogToTableWithOverwrite                 Job history is written to a log table, overwriting previous contents.
None                                    Job history is not appended to a file.
ProvideStopProcessEvent                 Job processing is stopped.

.PARAMETER ProxyName
The name of the proxy that the job step runs as.

.NOTES 
Original Author: Sander Stad (@sqlstad, sqlstad.nl)
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Set-DbaAgentJobStep

.EXAMPLE   
Set-DbaAgentJobStep -SqlInstance 'sql' -JobName 'Job1' -StepName 'Step1' -NewName 'Step2'
Changes the name of the step in "Job1" with the name "Step1" to "Step2"

.EXAMPLE   
Set-DbaAgentJobStep -SqlInstance 'sql' -JobName 'Job1' -StepName 'Step1' -Database 'msdb'
Changes the database of the step in "Job1" with the name "Step1" to 'msdb'

.EXAMPLE   
Set-DbaAgentJobStep -SqlInstance 'sql' -JobName 'Job1', 'Job2' -StepName 'Step1' -Database 'msdb'
Changes job steps in multiple jobs with the name "Step1" to 'msdb'

.EXAMPLE   
Set-DbaAgentJobStep -SqlInstance 'sql', 'sql2', 'sql3' -JobName 'Job1', 'Job2' -StepName 'Step1' -Database 'msdb'
Changes job steps in multiple jobs on multiple servers with the name "Step1" to 'msdb'

.EXAMPLE   
Set-DbaAgentJobStep -SqlInstance "sql1", "sql2", "sql3" -JobName 'Job1' -StepName 'Step1' -DatabaseName 'msdb'
Changes the database of the step in "Job1" with the name "Step1" to 'msdb' for multiple servers

.EXAMPLE   
"sql1", "sql2", "sql3" | Set-DbaAgentJobStep -JobName 'Job1' -StepName 'Step1' -DatabaseName 'msdb'
Changes the database of the step in "Job1" with the name "Step1" to 'msdb' for multiple servers using pipe line

#>   
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]

    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object[]]$SqlInstance,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$JobName,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StepName,
        [Parameter(Mandatory = $false)]
        [string]$NewName,
        [Parameter(Mandatory = $false)]
        [ValidateSet('ActiveScripting', 'AnalysisCommand', 'AnalysisQuery', 'CmdExec', 'Distribution', 'LogReader', 'Merge', 'PowerShell', 'QueueReader', 'Snapshot', 'Ssis', 'TransactSql')]
        [string]$Subsystem,
        [Parameter(Mandatory = $false)]
        [string]$Command,
        [Parameter(Mandatory = $false)]
        [int]$CmdExecSuccessCode,
        [Parameter(Mandatory = $false)]
        [ValidateSet('QuitWithSuccess', 'QuitWithFailure', 'GoToNextStep', 'GoToStep')]
        [string]$OnSuccessAction,
        [Parameter(Mandatory = $false)]
        [int]$OnSuccessStepId,
        [Parameter(Mandatory = $false)]
        [ValidateSet('QuitWithSuccess', 'QuitWithFailure', 'GoToNextStep', 'GoToStep')]
        [string]$OnFailAction,
        [Parameter(Mandatory = $false)]
        [int]$OnFailStepId,
        [Parameter(Mandatory = $false)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $false)]
        [string]$DatabaseUserName,
        [Parameter(Mandatory = $false)]
        [int]$RetryAttempts,
        [Parameter(Mandatory = $false)]
        [int]$RetryInterval,
        [Parameter(Mandatory = $false)]
        [string]$OutputFileName,
        [Parameter(Mandatory = $false)]
        [ValidateSet('AppendAllCmdExecOutputToJobHistory', 'AppendToJobHistory', 'AppendToLogFile', 'LogToTableWithOverwrite', 'None', 'ProvideStopProcessEvent')]
        [string[]]$Flag,
        [Parameter(Mandatory = $false)]
        [string]$ProxyName,
        [switch]$Silent
    )

    begin {
        # Check the parameter on success step id
        if (($OnSuccessAction -ne 'GoToStep') -and ($OnSuccessStepId -ge 1)) {
            Stop-Function -Message "Parameter OnSuccessStepId can only be used with OnSuccessAction 'GoToStep'."  -Target $SqlInstance 
            return
        }

        # Check the parameter on success step id
        if (($OnFailAction -ne 'GoToStep') -and ($OnFailStepId -ge 1)) {
            Stop-Function -Message "Parameter OnFailStepId can only be used with OnFailAction 'GoToStep'."  -Target $SqlInstance 
            return
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $sqlinstance) {

            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to Sql Server.." -Level Output 
            try {
                $Server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Could not connect to Sql Server instance" -Target $instance -Continue
                return
            }

            foreach ($j in $JobName) {

                # Check if the job exists
                if (($Server.JobServer.Jobs).Name -notcontains $j) {
                    Stop-Function -Message "Job $j doesn't exists on $instance" -Target $instance -Continue
                    return
                }
                else {
                    # Check if the job step exists
                    if (($Server.JobServer.Jobs[$j].JobSteps).Name -notcontains $StepName) {
                        Stop-Function -Message "Step $StepName doesn't exists on $instance" -Target $instance -Continue
                        return
                    }
                    else {
                        # Get the job step
                        $JobStep = $Server.JobServer.Jobs[$j].JobSteps[$StepName]

                        #region job step options
                        # Setting the options for the job step
                        if ($NewName) {
                            Write-Message -Message "Setting job step name to $NewName" -Level Verbose 
                            $JobStep.Rename($NewName)
                        }

                        if ($Subsystem) {
                            Write-Message -Message "Setting job step subsystem to $Subsystem" -Level Verbose 
                            $JobStep.Subsystem = $Subsystem
                        }

                        if ($Command) {
                            Write-Message -Message "Setting job step command to $Command" -Level Verbose 
                            $JobStep.Command = $Command
                        }

                        if ($CmdExecSuccessCode) {
                            Write-Message -Message "Setting job step command exec success code to $CmdExecSuccessCode" -Level Verbose 
                            $JobStep.CommandExecutionSuccessCode = $CmdExecSuccessCode
                        }

                        if ($OnSuccessAction) {
                            Write-Message -Message "Setting job step success action to $OnSuccessAction" -Level Verbose 
                            $JobStep.OnSuccessAction = $OnSuccessAction
                        }

                        if ($OnSuccessStepId) {
                            Write-Message -Message "Setting job step success step id to $OnSuccessStepId" -Level Verbose 
                            $JobStep.OnSuccessStep = $OnSuccessStepId
                        }

                        if ($OnFailAction) {
                            Write-Message -Message "Setting job step fail action to $OnFailAction" -Level Verbose 
                            $JobStep.OnFailAction = $OnFailAction
                        }

                        if ($OnFailStepId) {
                            Write-Message -Message "Setting job step fail step id to $OnFailStepId" -Level Verbose 
                            $JobStep.OnFailStep = $OnFailStepId
                        }

                        if ($DatabaseName) {
                            # Check if the database is present on the server
                            if (($Server.Databases).Name -contains $DatabaseName) {
                                Write-Message -Message "Setting job step database name to $DatabaseName" -Level Verbose 
                                $JobStep.DatabaseName = $DatabaseName
                            }
                            else {
                                Stop-Function -Message "The database is not present on instance $instance." -Target $SqlInstance -Continue
                                return
                            }
                        }

                        if (($DatabaseUserName) -and ($DatabaseName)) {
                            # Check if the username is present in the database
                            if (($Server.Databases[$DatabaseName].Users).Name -contains $DatabaseUserName) {
                                Write-Message -Message "Setting job step database username to $DatabaseUserName" -Level Verbose 
                                $JobStep.DatabaseUserName = $DatabaseUserName
                            }
                            else {
                                Stop-Function -Message "The database user is not present in the database $DatabaseName on instance $instance." -Target $SqlInstance -Continue
                                return
                            }
                        }

                        if ($RetryAttempts) {
                            Write-Message -Message "Setting job step retry attempts to $RetryAttempts" -Level Verbose 
                            $JobStep.RetryAttempts = $RetryAttempts
                        }

                        if ($RetryInterval) {
                            Write-Message -Message "Setting job step retry interval to $RetryInterval" -Level Verbose 
                            $JobStep.RetryInterval = $RetryInterval
                        }

                        if ($OutputFileName) {
                            Write-Message -Message "Setting job step output file name to $OutputFileName" -Level Verbose 
                            $JobStep.OutputFileName = $OutputFileName
                        }

                        if ($ProxyName) {
                            # Check if the proxy exists
                            if (($Server.JobServer.ProxyAccounts).Name -contains $ProxyName) {
                                Write-Message -Message "Setting job step proxy name to $ProxyName" -Level Verbose 
                                $JobStep.ProxyName = $ProxyName
                            }
                            else {
                                Stop-Function -Message "The proxy name $ProxyName doesn't exist on instance $instance." -Target $instance -Continue
                                return
                            }
                        }

                        if ($Flag.Count -ge 1) {
                            Write-Message -Message "Setting job step flag(s) to $($Flags -join ',')" -Level Verbose 
                            $JobStep.JobStepFlags = $Flag
                        }
                        #region job step options

                        # Execute 
                        if ($PSCmdlet.ShouldProcess($SqlServer, ("Changing the job step $StepName"))) {
                            try {
                                Write-Message -Message "Changing the job step" -Level Output 
                        
                                # Change the job step
                                $JobStep.Alter()
                            }
                            catch {
                                Stop-Function -Message "Something went wrong changing the job step. `n$_.Exception.Message)" -Target $instance -Continue
                                return
                            }
                        }
                    }
                }

            }

        }
    }

    end {
        Write-Message -Message "Finished changing job step(s)." -Level Output 
    }
}