function New-DbaAgentJobStep
{
<#
.SYNOPSIS 
New-DbaAgentJobStep creates a new job step for a job

.DESCRIPTION
New-DbaAgentJobStep creates a new job in the SQL Server Agent for a specific job

.PARAMETER SqlServer
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER JobName
The name of the job to which to add the step.

.PARAMETER StepId
The sequence identification number for the job step. Step identification numbers start at 1 and increment without gaps.

.PARAMETER StepName
The name of the step.

.PARAMETER SubSystem
The subsystem used by the SQL Server Agent service to execute command.
Allowed values 'ActiveScripting','AnalysisCommand','AnalysisQuery','CmdExec','Distribution','LogReader','Merge','PowerShell','QueueReader','Snapshot','Ssis','TransactSql'
The default is 'TransactSql'

.PARAMETER Command
The commands to be executed by SQLServerAgent service through subsystem.

.PARAMETER CmdExecSuccessCode 
The value returned by a CmdExec subsystem command to indicate that command executed successfully.

.PARAMETER OnSuccessAction 
The action to perform if the step succeeds.
Allowed values  "QuitWithSuccess" (default), "QuitWithFailure", "GoToNextStep", "GoToStep".
The text value van either be lowercase, uppercase or something in between as long as the text is correct.

.PARAMETER OnSuccessStepId 
The ID of the step in this job to execute if the step succeeds and OnSuccessAction is "GoToStep".

.PARAMETER OnFailAction 
The action to perform if the step fails.
Allowed values  "QuitWithSuccess" (default), "QuitWithFailure", "GoToNextStep", "GoToStep".
The text value van either be lowercase, uppercase or something in between as long as the text is correct.

.PARAMETER OnFailStepId 
The ID of the step in this job to execute if the step fails and OnFailAction is "GoToNextStep".

.PARAMETER DatabaseName
The name of the database in which to execute a Transact-SQL step. The default is 'master'.

.PARAMETER DatabaseUserName 
The name of the user account to use when executing a Transact-SQL step. 

.PARAMETER RetryAttempts
The number of retry attempts to use if this step fails. The default is 0.

.PARAMETER RetryInterval
The amount of time in minutes between retry attempts. The default is 0.

.PARAMETER OutputFileName
The name of the file in which the output of this step is saved.

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
https://dbatools.io/New-DbaAgentJobStep

.EXAMPLE   
New-DbaAgentJobStep -SqlServer 'sql' -JobName 'Job1' -StepName 'Step1'
Create a step in "Job1" with the name "Step1" with the default subsystem TransactSql.

.EXAMPLE   
New-DbaAgentJobStep -SqlServer 'sql' -JobName 'Job1' -StepName 'Step1' -Database 'msdb'
Create a step in "Job1" with the name "Step1" where the database will the "msdb"

#>

    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]

    param(
        [parameter(Mandatory = $true, ValueFromPipeline=$true)]
		[object[]]$SqlServer,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$JobName,
        [Parameter(Mandatory = $false)]
        [int]$StepId,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StepName,
        [Parameter(Mandatory = $false)]
        [ValidateSet('ActiveScripting','AnalysisCommand','AnalysisQuery','CmdExec','Distribution','LogReader','Merge','PowerShell','QueueReader','Snapshot','Ssis','TransactSql')]
        [string]$Subsystem = 'TransactSql',
        [Parameter(Mandatory = $false)]
        [string]$Command,
        [Parameter(Mandatory = $false)]
        [int]$CmdExecSuccessCode = 0,
        [Parameter(Mandatory = $false)]
        [ValidateSet('QuitWithSuccess', 'QuitWithFailure', 'GoToNextStep', 'GoToStep')]
        [string]$OnSuccessAction = 'QuitWithSuccess',
        [Parameter(Mandatory = $false)]
        [int]$OnSuccessStepId = 0,
        [Parameter(Mandatory = $false)]
        [ValidateSet('QuitWithSuccess', 'QuitWithFailure', 'GoToNextStep', 'GoToStep')]
        [string]$OnFailAction = 'QuitWithFailure',
        [Parameter(Mandatory = $false)]
        [int]$OnFailStepId = 0,
        [Parameter(Mandatory = $false)]
        [string]$DatabaseName = 'master',
        [Parameter(Mandatory = $false)]
        [string]$DatabaseUserName,
        [Parameter(Mandatory = $false)]
        [int]$RetryAttempts = 0,
        [Parameter(Mandatory = $false)]
        [int]$RetryInterval = 0,
        [Parameter(Mandatory = $false)]
        [string]$OutputFileName,
        [Parameter(Mandatory = $false)]
        [string]$ProxyName,
        [switch]$Silent
    )

    BEGIN
    {
        # Check the values for the success step id
        if(($OnSuccessStepId -ge 1) -and ($OnSuccessAction -ne 'GoToStep'))
        {
            Stop-Function -Message "Parameter OnSuccessStepId can only be used with OnSuccessAction 4 or 'StepId'." -Silent $Silent -InnerErrorRecord $_ -Target $SqlServer 
            return
        }

        # Check the values for the failure step id
        if(($OnFailStepId -ge 1) -and ($OnFailAction -ne 'GoToStep'))
        {
            Stop-Function -Message "Parameter OnFailStepId can only be used with OnFailAction 4 or 'StepId'." -Silent $Silent -InnerErrorRecord $_ -Target $SqlServer 
            return
        }
    }

    PROCESS
    {
        # Try connecting to the instance
        Write-Message -Message "Attempting to connect to Sql Server.." -Level 2 -Silent $Silent
        try 
        {
            $Server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
        }
        catch 
        {
            Stop-Function -Message "Could not connect to Sql Server instance" -Silent $Silent -InnerErrorRecord $_ -Target $SqlServer 
            return
        }

        # Check if the job exists
        if(($Server.JobServer.Jobs).Name -notcontains $JobName)
        {
            Write-Message -Message "Job '$($JobName)' doesn't exists on '$($SqlServer)'" -Warning -Silent $Silent
        }
        else 
        {
            # Create the job step object
            try 
            {
                # Get the job
                $Job = $Server.JobServer.Jobs[$JobName]
                
                # Create the job step
                $JobStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep

                # Set the job where the job steps belongs to
                $JobStep.Parent = $Job
            }
            catch 
            {
                Stop-Function -Message ("Something went wrong creating the job step. `n$($_.Exception.Message)") -Silent $Silent -InnerErrorRecord $_ -Target $StepName
                return
            }

            #region job step options
            # Setting the options for the job step
            if($StepName.Length -ge 1)
            {
                # Check if the step already exists
                if(($Server.JobServer.Jobs[$JobName].JobSteps).Name -notcontains $StepName)
                {
                    $JobStep.Name = $StepName
                }
                else 
                {
                    Stop-Function -Message ("The step name '$($StepName)' is already exists.") -Silent $Silent -InnerErrorRecord $_ -Target $StepName
                    return
                }
                
            }

            if($StepId -ge 1)
            {
                # Check if the used step id is already in place
                if($Job.JobSteps.ID -notcontains $StepId)
                {
                    Write-Message -Message "Setting job step step id to $($StepId)" -Level 5 -Silent $Silent
                    $JobStep.ID = $StepId
                }
                else
                {
                    Stop-Function -Message ("The step id $($StepId) is already exists.") -Silent $Silent -InnerErrorRecord $_ -Target $StepName
                    return
                }
                
            }
            else 
            {
                # Get the job step count
                $JobStep.ID = $Job.JobSteps.Count + 1
            }

            if($Subsystem.Length -ge 1)
            {
                Write-Message -Message "Setting job step subsystem to '$($Subsystem)'" -Level 5 -Silent $Silent
                $JobStep.Subsystem = $Subsystem
            }

            if($Command.Length -ge 1)
            {
                Write-Message -Message "Setting job step command to '$($Command)'" -Level 5 -Silent $Silent
                $JobStep.Command = $Command
            }

            if($CmdExecSuccessCode -ge 0)
            {
                Write-Message -Message "Setting job step command exec success code to $($CmdExecSuccessCode)" -Level 5 -Silent $Silent
                $JobStep.CommandExecutionSuccessCode = $CmdExecSuccessCode
            }

            if($OnSuccessAction.Length -ge 1)
            {
                Write-Message -Message "Setting job step success action to '$($OnSuccessAction)'" -Level 5 -Silent $Silent
                $JobStep.OnSuccessAction = $OnSuccessAction
            }

            if($OnSuccessStepId -ge 1)
            {
                Write-Message -Message "Setting job step success step id to $($OnSuccessStepId)" -Level 5 -Silent $Silent
                $JobStep.OnSuccessStep = $OnSuccessStepId
            }

            if($OnFailAction.Length -ge 1)
            {
                Write-Message -Message "Setting job step fail action to '$($OnFailAction)'" -Level 5 -Silent $Silent
                $JobStep.OnFailAction = $OnFailAction
            }

            if($OnFailStepId -ge 1)
            {
                Write-Message -Message "Setting job step fail step id to $($OnFailStepId)" -Level 5 -Silent $Silent
                $JobStep.OnFailStep = $OnFailStepId
            }

            if($DatabaseName.Length -ge 1)
            {
                # Check if the database is present on the server
                if(($Server.Databases).Name -contains $DatabaseName)
                {
                    Write-Message -Message "Setting job step database name to '$($DatabaseName)'" -Level 5 -Silent $Silent
                    $JobStep.DatabaseName = $DatabaseName
                }
                else 
                {
                    Stop-Function -Message ("The database is not present on instance '$($SqlServer)'.") -Silent $Silent -InnerErrorRecord $_ -Target $JobName
                    return
                }
            }

            if(($DatabaseUserName.Length -ge 1) -and ($DatabaseName.Length -ge 1))
            {
                # Check if the username is present in the database
                if(($Server.Databases[$DatabaseName].Users).Name -contains $DatabaseUserName)
                {
                    
                    Write-Message -Message "Setting job step database username to '$($DatabaseUserName)'" -Level 5 -Silent $Silent
                    $JobStep.DatabaseUserName = $DatabaseUserName
                }
                else 
                {
                    Stop-Function -Message ("The database user is not present in the database '$($DatabaseName)' on instance '$($SqlServer)'.") -Silent $Silent -InnerErrorRecord $_ -Target $StepName
                    return
                }
            }

            if($RetryAttempts -ge 1)
            {
                Write-Message -Message "Setting job step retry attempts to $($RetryAttempts)" -Level 5 -Silent $Silent
                $JobStep.RetryAttempts = $RetryAttempts
            }

            if($RetryInterval -ge 1)
            {
                Write-Message -Message "Setting job step retry interval to $($RetryInterval)" -Level 5 -Silent $Silent
                $JobStep.RetryInterval = $RetryInterval
            }

            if($OutputFileName.Length -ge 1)
            {
                Write-Message -Message "Setting job step output file name to '$($OutputFileName)'" -Level 5 -Silent $Silent
                $JobStep.OutputFileName = $OutputFileName
            }

            if($ProxyName.Length -ge 1)
            {
                # Check if the proxy exists
                if(($Server.JobServer.ProxyAccounts).Name -contains $ProxyName)
                {
                    Write-Message -Message "Setting job step proxy name to $($ProxyName)" -Level 5 -Silent $Silent
                    $JobStep.ProxyName = $ProxyName
                }
                else 
                {
                    Stop-Function -Message ("The proxy name '$($ProxyName)' doesn't exist on instance '$($SqlServer)'.") -Silent $Silent -InnerErrorRecord $_ -Target $StepName
                    return
                }
            }
            #endregion job step options

            # Execute 
            if($PSCmdlet.ShouldProcess($SqlServer, ("Creating the job step '$($StepName)'"))) 
            {
                try
                {
                    Write-Message -Message ("Creating the job step") -Level 2 -Silent $Silent
                    
                    # Create the job step 
                    $JobStep.Create()
                    $Job.Alter()
                }
                catch
                {
                    Write-Message -Message ("Something went wrong creating the job step. `n$($_.Exception.Message)") -Level 2 -Silent $Silent 
                }

            }
        }
    }

    END
    {
        Write-Message -Message "Creation of job step(s) completed" -Level 2 -Silent $Silent
    }
}