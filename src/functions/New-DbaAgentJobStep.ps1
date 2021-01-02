function New-DbaAgentJobStep {
    <#
    .SYNOPSIS
        New-DbaAgentJobStep creates a new job step for a job

    .DESCRIPTION
        New-DbaAgentJobStep creates a new job in the SQL Server Agent for a specific job

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job to which to add the step.

    .PARAMETER StepId
        The sequence identification number for the job step. Step identification numbers start at 1 and increment without gaps.

    .PARAMETER StepName
        The name of the step.

    .PARAMETER SubSystem
        The subsystem used by the SQL Server Agent service to execute command.
        Allowed values 'ActiveScripting','AnalysisCommand','AnalysisQuery','CmdExec','Distribution','LogReader','Merge','PowerShell','QueueReader','Snapshot','Ssis','TransactSql'
        The default is 'TransactSql'

    .PARAMETER SubSystemServer
        The subsystems AnalysisScripting, AnalysisCommand, AnalysisQuery ned the server property to be able to apply

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
        The ID of the step in this job to execute if the step fails and OnFailAction is "GoToStep".

    .PARAMETER Database
        The name of the database in which to execute a Transact-SQL step. The default is 'master'.

    .PARAMETER DatabaseUser
        The name of the user account to use when executing a Transact-SQL step.

    .PARAMETER RetryAttempts
        The number of retry attempts to use if this step fails. The default is 0.

    .PARAMETER RetryInterval
        The amount of time in minutes between retry attempts. The default is 0.

    .PARAMETER OutputFileName
        The name of the file in which the output of this step is saved.

    .PARAMETER Insert
        This switch indicates the new step is inserted at the specified stepid.
        All following steps will have their IDs incremented by, and success/failure next steps incremented accordingly

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

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job, JobStep
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaAgentJobStep

    .EXAMPLE
        PS C:\> New-DbaAgentJobStep -SqlInstance sql1 -Job Job1 -StepName Step1

        Create a step in "Job1" with the name Step1 with the default subsystem TransactSql.

    .EXAMPLE
        PS C:\> New-DbaAgentJobStep -SqlInstance sql1 -Job Job1 -StepName Step1 -Database msdb

        Create a step in "Job1" with the name Step1 where the database will the msdb

    .EXAMPLE
        PS C:\> New-DbaAgentJobStep -SqlInstance sql1, sql2, sql3 -Job Job1 -StepName Step1 -Database msdb

        Create a step in "Job1" with the name Step1 where the database will the "msdb" for multiple servers

    .EXAMPLE
        PS C:\> New-DbaAgentJobStep -SqlInstance sql1, sql2, sql3 -Job Job1, Job2, 'Job Three' -StepName Step1 -Database msdb

        Create a step in "Job1" with the name Step1 where the database will the "msdb" for multiple servers for multiple jobs

    .EXAMPLE
        PS C:\> sql1, sql2, sql3 | New-DbaAgentJobStep -Job Job1 -StepName Step1 -Database msdb

        Create a step in "Job1" with the name Step1 where the database will the "msdb" for multiple servers using pipeline

    .EXAMPLE
        PS C:\> New-DbaAgentJobStep -SqlInstance sq1 -Job Job1 -StepName StepA -Database msdb -StepId 2 -Insert

        Assuming Job1 already has steps Step1 and Step2, will create a new step Step A and set the step order as Step1, StepA, Step2
        Internal StepIds will be updated, and any specific OnSuccess/OnFailure step references will also be updated

    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Job,
        [int]$StepId,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StepName,
        [ValidateSet('ActiveScripting', 'AnalysisCommand', 'AnalysisQuery', 'CmdExec', 'Distribution', 'LogReader', 'Merge', 'PowerShell', 'QueueReader', 'Snapshot', 'Ssis', 'TransactSql')]
        [string]$Subsystem = 'TransactSql',
        [string]$SubsystemServer,
        [string]$Command,
        [int]$CmdExecSuccessCode,
        [ValidateSet('QuitWithSuccess', 'QuitWithFailure', 'GoToNextStep', 'GoToStep')]
        [string]$OnSuccessAction = 'QuitWithSuccess',
        [int]$OnSuccessStepId = 0,
        [ValidateSet('QuitWithSuccess', 'QuitWithFailure', 'GoToNextStep', 'GoToStep')]
        [string]$OnFailAction = 'QuitWithFailure',
        [int]$OnFailStepId = 0,
        [object]$Database,
        [string]$DatabaseUser,
        [int]$RetryAttempts,
        [int]$RetryInterval,
        [string]$OutputFileName,
        [switch]$Insert,
        [ValidateSet('AppendAllCmdExecOutputToJobHistory', 'AppendToJobHistory', 'AppendToLogFile', 'AppendToTableLog', 'LogToTableWithOverwrite', 'None', 'ProvideStopProcessEvent')]
        [string[]]$Flag,
        [string]$ProxyName,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Check the parameter on success step id
        if (($OnSuccessAction -ne 'GoToStep') -and ($OnSuccessStepId -ge 1)) {
            Stop-Function -Message "Parameter OnSuccessStepId can only be used with OnSuccessAction 'GoToStep'." -Target $SqlInstance
            return
        }

        # Check the parameter on fail step id
        if (($OnFailAction -ne 'GoToStep') -and ($OnFailStepId -ge 1)) {
            Stop-Function -Message "Parameter OnFailStepId can only be used with OnFailAction 'GoToStep'." -Target $SqlInstance
            return
        }

        if ($Subsystem -in 'AnalysisScripting', 'AnalysisCommand', 'AnalysisQuery') {
            if (-not $SubsystemServer) {
                Stop-Function -Message "Please enter the server value using -SubSystemServer for subsystem $Subsystem." -Target $Subsystem
                return
            }
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $Server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    Write-Message -Message "Job $j doesn't exists on $instance" -Level Warning
                } else {
                    # Create the job step object
                    try {
                        # Get the job
                        $currentJob = $Server.JobServer.Jobs[$j]

                        # Create the job step
                        $jobStep = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobStep

                        # Set the job where the job steps belongs to
                        $jobStep.Parent = $currentJob
                    } catch {
                        Stop-Function -Message "Something went wrong creating the job step" -Target $instance -ErrorRecord $_ -Continue
                    }

                    #region job step options
                    # Setting the options for the job step
                    if ($StepName) {
                        # Check if the step already exists
                        if ($Server.JobServer.Jobs[$j].JobSteps.Name -notcontains $StepName) {
                            $jobStep.Name = $StepName
                        } elseif (($Server.JobServer.Jobs[$j].JobSteps.Name -contains $StepName) -and $Force) {
                            Write-Message -Message "Step $StepName already exists for job. Force is used. Removing existing step" -Level Verbose

                            # Remove the job step based on the name
                            Remove-DbaAgentJobStep -SqlInstance $instance -Job $currentJob -StepName $StepName -SqlCredential $SqlCredential

                            # Set the name job step object
                            $jobStep.Name = $StepName
                        } else {
                            Stop-Function -Message "The step name $StepName already exists for job $j" -Target $instance -Continue
                        }
                    }

                    # If the step id need to be set
                    if ($StepId) {
                        # Check if the used step id is already in place
                        if ($Job.JobSteps.ID -notcontains $StepId) {
                            Write-Message -Message "Setting job step step id to $StepId" -Level Verbose
                            $jobStep.ID = $StepId
                        } elseif (($Job.JobSteps.ID -contains $StepID) -and $Insert) {
                            Write-Message -Message "Inserting step as step $StepID" -Level Verbose
                            foreach ($tStep in $Server.JobServer.Jobs[$j].JobSteps) {
                                if ($tStep.Id -ge $Stepid) {
                                    $tStep.Id = ($tStep.ID) + 1
                                }
                                if ($tStep.OnFailureStepID -ge $StepId -and $tStep.OnFailureStepId -ne 0) {
                                    $tStep.OnFailureStepID = ($tStep.OnFailureStepID) + 1
                                }
                            }
                            $jobStep.ID = $StepId
                        } elseif (($Job.JobSteps.ID -contains $StepId) -and $Force) {
                            Write-Message -Message "Step ID $StepId already exists for job. Force is used. Removing existing step" -Level Verbose

                            # Remove the existing job step
                            $StepName = ($Server.JobServer.Jobs[$j].JobSteps | Where-Object { $_.ID -eq 1 }).Name
                            Remove-DbaAgentJobStep -SqlInstance $instance -Job $currentJob -StepName $StepName -SqlCredential $SqlCredential

                            # Set the ID job step object
                            $jobStep.ID = $StepId
                        } else {
                            Stop-Function -Message "The step id $StepId already exists for job $j" -Target $instance -Continue
                        }
                    } else {
                        # Get the job step count
                        $jobStep.ID = $Job.JobSteps.Count + 1
                    }

                    if ($Subsystem) {
                        Write-Message -Message "Setting job step subsystem to $Subsystem" -Level Verbose
                        $jobStep.Subsystem = $Subsystem
                    }

                    if ($SubsystemServer) {
                        Write-Message -Message "Setting job step subsystem server to $SubsystemServer" -Level Verbose
                        $jobStep.Server = $SubsystemServer
                    }

                    if ($Command) {
                        Write-Message -Message "Setting job step command to $Command" -Level Verbose
                        $jobStep.Command = $Command
                    }

                    if ($CmdExecSuccessCode) {
                        Write-Message -Message "Setting job step command exec success code to $CmdExecSuccessCode" -Level Verbose
                        $jobStep.CommandExecutionSuccessCode = $CmdExecSuccessCode
                    }

                    if ($OnSuccessAction) {
                        Write-Message -Message "Setting job step success action to $OnSuccessAction" -Level Verbose
                        $jobStep.OnSuccessAction = $OnSuccessAction
                    }

                    if ($OnSuccessStepId) {
                        Write-Message -Message "Setting job step success step id to $OnSuccessStepId" -Level Verbose
                        $jobStep.OnSuccessStep = $OnSuccessStepId
                    }

                    if ($OnFailAction) {
                        Write-Message -Message "Setting job step fail action to $OnFailAction" -Level Verbose
                        $jobStep.OnFailAction = $OnFailAction
                    }

                    if ($OnFailStepId) {
                        Write-Message -Message "Setting job step fail step id to $OnFailStepId" -Level Verbose
                        $jobStep.OnFailStep = $OnFailStepId
                    }

                    if ($Database) {
                        # Check if the database is present on the server
                        if ($Server.Databases.Name -contains $Database) {
                            Write-Message -Message "Setting job step database name to $Database" -Level Verbose
                            $jobStep.DatabaseName = $Database
                        } else {
                            Stop-Function -Message "The database is not present on instance $instance." -Target $instance -Continue
                        }
                    }

                    if ($DatabaseUser -and $DatabaseName) {
                        # Check if the username is present in the database
                        if ($Server.Databases[$DatabaseName].Users.Name -contains $DatabaseUser) {

                            Write-Message -Message "Setting job step database username to $DatabaseUser" -Level Verbose
                            $jobStep.DatabaseUserName = $DatabaseUser
                        } else {
                            Stop-Function -Message "The database user is not present in the database $DatabaseName on instance $instance." -Target $instance -Continue
                        }
                    }

                    if ($RetryAttempts) {
                        Write-Message -Message "Setting job step retry attempts to $RetryAttempts" -Level Verbose
                        $jobStep.RetryAttempts = $RetryAttempts
                    }

                    if ($RetryInterval) {
                        Write-Message -Message "Setting job step retry interval to $RetryInterval" -Level Verbose
                        $jobStep.RetryInterval = $RetryInterval
                    }

                    if ($OutputFileName) {
                        Write-Message -Message "Setting job step output file name to $OutputFileName" -Level Verbose
                        $jobStep.OutputFileName = $OutputFileName
                    }

                    if ($ProxyName) {
                        # Check if the proxy exists
                        if ($Server.JobServer.ProxyAccounts.Name -contains $ProxyName) {
                            Write-Message -Message "Setting job step proxy name to $ProxyName" -Level Verbose
                            $jobStep.ProxyName = $ProxyName
                        } else {
                            Stop-Function -Message "The proxy name $ProxyName doesn't exist on instance $instance." -Target $instance -Continue
                        }
                    }

                    if ($Flag.Count -ge 1) {
                        Write-Message -Message "Setting job step flag(s) to $($Flags -join ',')" -Level Verbose
                        $jobStep.JobStepFlags = $Flag
                    }
                    #endregion job step options

                    # Execute
                    if ($PSCmdlet.ShouldProcess($instance, "Creating the job step $StepName")) {
                        try {
                            Write-Message -Message "Creating the job step" -Level Verbose

                            # Create the job step
                            $jobStep.Create()
                            $currentJob.Alter()
                        } catch {
                            Stop-Function -Message "Something went wrong creating the job step" -Target $instance -ErrorRecord $_ -Continue
                        }

                        # Return the job step
                        $jobStep
                    }
                }
            } # foreach object job
        } # foreach object instance
    } # process

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished creating job step(s)" -Level Verbose
    }
}