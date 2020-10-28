function Set-DbaAgentJobStep {
    <#
    .SYNOPSIS
        Set-DbaAgentJobStep updates a job step.

    .DESCRIPTION
        Set-DbaAgentJobStep updates a job step in the SQL Server Agent with parameters supplied.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job. Can be null if the the job id is being used.

    .PARAMETER StepName
        The name of the step.

    .PARAMETER NewName
        The new name for the step in case it needs to be renamed.

    .PARAMETER SubSystem
        The subsystem used by the SQL Server Agent service to execute command.
        Allowed values 'ActiveScripting','AnalysisCommand','AnalysisQuery','CmdExec','Distribution','LogReader','Merge','PowerShell','QueueReader','Snapshot','Ssis','TransactSql'

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
        The ID of the step in this job to execute if the step succeeds and OnSuccessAction is "GoToNextStep".

    .PARAMETER OnFailAction
        The action to perform if the step fails.
        Allowed values  "QuitWithSuccess" (default), "QuitWithFailure", "GoToNextStep", "GoToStep".
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER OnFailStepId
        The ID of the step in this job to execute if the step fails and OnFailAction is "GoToNextStep".

    .PARAMETER Database
        The name of the database in which to execute a Transact-SQL step. The default is 'master'.

    .PARAMETER DatabaseUser
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

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER InputObject
        Enables piping job objects

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

    .NOTES
        Tags: Agent, Job, JobStep
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentJobStep

    .EXAMPLE
        PS C:\> Set-DbaAgentJobStep -SqlInstance sql1 -Job Job1 -StepName Step1 -NewName Step2

        Changes the name of the step in "Job1" with the name Step1 to Step2

    .EXAMPLE
        PS C:\> Set-DbaAgentJobStep -SqlInstance sql1 -Job Job1 -StepName Step1 -Database msdb

        Changes the database of the step in "Job1" with the name Step1 to msdb

    .EXAMPLE
        PS C:\> Set-DbaAgentJobStep -SqlInstance sql1 -Job Job1, Job2 -StepName Step1 -Database msdb

        Changes job steps in multiple jobs with the name Step1 to msdb

    .EXAMPLE
        PS C:\> Set-DbaAgentJobStep -SqlInstance sql1, sql2, sql3 -Job Job1, Job2 -StepName Step1 -Database msdb

        Changes job steps in multiple jobs on multiple servers with the name Step1 to msdb

    .EXAMPLE
        PS C:\> Set-DbaAgentJobStep -SqlInstance sql1, sql2, sql3 -Job Job1 -StepName Step1 -Database msdb

        Changes the database of the step in "Job1" with the name Step1 to msdb for multiple servers

    .EXAMPLE
        PS C:\> sql1, sql2, sql3 | Set-DbaAgentJobStep -Job Job1 -StepName Step1 -Database msdb

        Changes the database of the step in "Job1" with the name Step1 to msdb for multiple servers using pipeline

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [string]$StepName,
        [string]$NewName,
        [ValidateSet('ActiveScripting', 'AnalysisCommand', 'AnalysisQuery', 'CmdExec', 'Distribution', 'LogReader', 'Merge', 'PowerShell', 'QueueReader', 'Snapshot', 'Ssis', 'TransactSql')]
        [string]$Subsystem,
        [string]$SubsystemServer,
        [string]$Command,
        [int]$CmdExecSuccessCode,
        [ValidateSet('QuitWithSuccess', 'QuitWithFailure', 'GoToNextStep', 'GoToStep')]
        [string]$OnSuccessAction,
        [int]$OnSuccessStepId,
        [ValidateSet('QuitWithSuccess', 'QuitWithFailure', 'GoToNextStep', 'GoToStep')]
        [string]$OnFailAction,
        [int]$OnFailStepId,
        [string]$Database,
        [string]$DatabaseUser,
        [int]$RetryAttempts,
        [int]$RetryInterval,
        [string]$OutputFileName,
        [ValidateSet('AppendAllCmdExecOutputToJobHistory', 'AppendToJobHistory', 'AppendToLogFile', 'AppendToTableLog', 'LogToTableWithOverwrite', 'None', 'ProvideStopProcessEvent')]
        [string[]]$Flag,
        [string]$ProxyName,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.JobStep[]]$InputObject,
        [switch]$EnableException,
        [switch]$Force
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Check the parameter on success step id
        if (($OnSuccessAction -ne 'GoToStep') -and ($OnSuccessStepId -ge 1)) {
            Stop-Function -Message "Parameter OnSuccessStepId can only be used with OnSuccessAction 'GoToStep'." -Target $SqlInstance
            return
        }

        # Check the parameter on success step id
        if (($OnFailAction -ne 'GoToStep') -and ($OnFailStepId -ge 1)) {
            Stop-Function -Message "Parameter OnFailStepId can only be used with OnFailAction 'GoToStep'." -Target $SqlInstance
            return
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $Job)) {
            Stop-Function -Message "You must specify a job name or pipe in results from another command" -Target $SqlInstance
            return
        }

        if ((-not $InputObject) -and (-not $StepName)) {
            Stop-Function -Message "You must specify a job step name or pipe in results from another command" -Target $SqlInstance
            return
        }

        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($server.JobServer.Jobs.Name -notcontains $j) {
                    Stop-Function -Message "Job $j doesn't exists on $instance" -Target $instance
                } else {
                    # Get the job step
                    try {
                        $InputObject += $server.JobServer.Jobs[$j].JobSteps | Where-Object Name -in $StepName

                        # Refresh the object
                        $InputObject.Refresh()
                    } catch {
                        Stop-Function -Message "Something went wrong retrieving the job step(s)" -Target $j -ErrorRecord $_ -Continue
                    }
                }
            }
        }

        if ($Job) {
            $InputObject = $InputObject | Where-Object { $_.Parent.Name -in $Job }
        }

        if ($StepName) {
            $InputObject = $InputObject | Where-Object Name -in $StepName
        }

        foreach ($instance in $SqlInstance) {

            # Try connecting to the instance
            try {
                $Server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($currentJobStep in $InputObject) {
                if (-not $Force -and ($Server.JobServer.Jobs[$currentJobStep.Parent.Name].JobSteps.Name -notcontains $currentJobStep.Name)) {
                    Stop-Function -Message "Step $StepName doesn't exists for job $j" -Target $instance -Continue
                } elseif ($Force -and ($Server.JobServer.Jobs[$currentJobStep.Parent.Name].JobSteps.Name -notcontains $currentJobStep.Name)) {
                    Write-Message -Message "Adding job step $($currentJobStep.Name) to $($currentJobStep.Parent.Name) on $instance" -Level Verbose

                    try {
                        $JobStep = New-DbaAgentJobStep -SqlInstance $instance -SqlCredential $SqlCredential `
                            -Job $currentJobStep.Parent.Name `
                            -StepId $currentJobStep.ID `
                            -StepName $currentJobStep.Name `
                            -Subsystem $currentJobStep.SubSystem `
                            -SubsystemServer $currentJobStep.Server `
                            -Command $currentJobStep.Command `
                            -CmdExecSuccessCode $currentJobStep.CmdExecSuccessCode `
                            -OnFailAction $currentJobStep.OnFailAction `
                            -OnSuccessAction $currentJobStep.OnSuccessAction `
                            -OnSuccessStepId $currentJobStep.OnSuccessStepId `
                            -OnFailStepId $currentJobStep.OnFailStepId `
                            -Database $currentJobStep.Database `
                            -DatabaseUser $currentJobStep.DatabaseUser `
                            -RetryAttempts $currentJobStep.RetryAttempts `
                            -RetryInterval $currentJobStep.RetryInterval `
                            -OutputFileName $currentJobStep.OutputFileName `
                            -Flag $currentJobStep.Flag `
                            -ProxyName $currentJobStep.ProxyName `
                            -EnableException
                    } catch {
                        Stop-Function -Message "Something went wrong creating the job step" -Target $instance -ErrorRecord $_ -Continue
                    }

                } else {
                    $JobStep = $server.JobServer.Jobs[$currentJobStep.Parent.Name].JobSteps[$currentJobStep.Name]
                }

                Write-Message -Message "Modifying job $j on $instance" -Level Verbose

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

                if ($SubsystemServer) {
                    Write-Message -Message "Setting job step subsystem server to $SubsystemServer" -Level Verbose
                    $JobStep.Server = $SubsystemServer
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

                if ($Database) {
                    # Check if the database is present on the server
                    if ($server.Databases.Name -contains $Database) {
                        Write-Message -Message "Setting job step database name to $Database" -Level Verbose
                        $JobStep.DatabaseName = $Database
                    } else {
                        Stop-Function -Message "The database is not present on instance $instance." -Target $instance -Continue
                    }
                }

                if (($DatabaseUser) -and ($Database)) {
                    # Check if the username is present in the database
                    if ($Server.Databases[$currentJobStep.DatabaseName].Users.Name -contains $DatabaseUser) {
                        Write-Message -Message "Setting job step database username to $DatabaseUser" -Level Verbose
                        $JobStep.DatabaseUserName = $DatabaseUser
                    } else {
                        Stop-Function -Message "The database user is not present in the database $($currentJobStep.DatabaseName) on instance $instance." -Target $instance -Continue
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
                    if ($Server.JobServer.ProxyAccounts.Name -contains $ProxyName) {
                        Write-Message -Message "Setting job step proxy name to $ProxyName" -Level Verbose
                        $JobStep.ProxyName = $ProxyName
                    } else {
                        Stop-Function -Message "The proxy name $ProxyName doesn't exist on instance $instance." -Target $instance -Continue
                    }
                }

                if ($Flag.Count -ge 1) {
                    Write-Message -Message "Setting job step flag(s) to $($Flags -join ',')" -Level Verbose
                    $JobStep.JobStepFlags = $Flag
                }
                #region job step options

                # Execute
                if ($PSCmdlet.ShouldProcess($instance, "Changing the job step $StepName for job $j")) {
                    try {
                        Write-Message -Message "Changing the job step $StepName for job $j" -Level Verbose

                        # Change the job step
                        $JobStep.Alter()
                    } catch {
                        Stop-Function -Message "Something went wrong changing the job step" -ErrorRecord $_ -Target $instance -Continue
                    }
                }

            } # end for each job step

        } # end for each instance

    } # process

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished changing job step(s)" -Level Verbose
    }
}