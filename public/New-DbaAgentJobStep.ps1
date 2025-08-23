function New-DbaAgentJobStep {
    <#
    .SYNOPSIS
        Creates a new step within an existing SQL Server Agent job with configurable execution options and flow control

    .DESCRIPTION
        Creates individual job steps within SQL Server Agent jobs, allowing you to build complex automation workflows without manually configuring each step through SSMS. Each step can execute different types of commands (T-SQL, PowerShell, SSIS packages, OS commands) and includes retry logic, success/failure branching, and output capture. When you need to add steps to existing jobs or build multi-step processes, this function handles the step ordering and dependency management automatically, including the ability to insert steps between existing ones without breaking the workflow sequence.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies the SQL Server Agent job name where the new step will be added. Accepts job names or job objects from Get-DbaAgentJob.
        Use this to target specific jobs when building multi-step automation workflows.

    .PARAMETER StepId
        Sets the execution order position for this step within the job sequence. Step numbers start at 1 and must be sequential.
        Use this to control step execution order or when inserting steps between existing ones. If not specified, adds the step at the end.

    .PARAMETER StepName
        Defines a descriptive name for the job step that appears in SQL Server Agent and job history logs.
        Choose meaningful names that clearly identify the step's purpose for easier troubleshooting and maintenance.

    .PARAMETER SubSystem
        Determines what execution engine SQL Server Agent uses to run the step command. Defaults to 'TransactSql' for T-SQL scripts.
        Use 'PowerShell' for PowerShell scripts, 'CmdExec' for operating system commands, 'Ssis' for SSIS packages, or replication subsystems for replication tasks.
        Analysis subsystems require SQL Server Analysis Services and the SubSystemServer parameter.

    .PARAMETER SubSystemServer
        Specifies the Analysis Services server name when using AnalysisScripting, AnalysisCommand, or AnalysisQuery subsystems.
        Required for Analysis Services job steps to connect to the appropriate SSAS instance for cube processing or MDX queries.

    .PARAMETER Command
        Contains the actual code or command that the job step will execute, such as T-SQL scripts, PowerShell code, or operating system commands.
        The command syntax must match the specified subsystem type. For T-SQL steps, include complete SQL statements or stored procedure calls.

    .PARAMETER CmdExecSuccessCode
        Defines the exit code that indicates successful completion for CmdExec subsystem steps. Most applications return 0 for success.
        Use this when running batch files or executables that return non-zero success codes to prevent the job from failing incorrectly.

    .PARAMETER OnSuccessAction
        Controls job flow when this step completes successfully. Default 'QuitWithSuccess' ends the job with success status.
        Use 'GoToNextStep' for sequential execution, 'GoToStep' to jump to a specific step, or 'QuitWithFailure' for conditional failure handling.
        Essential for building complex workflows with branching logic based on step outcomes.

    .PARAMETER OnSuccessStepId
        Specifies which step to execute next when OnSuccessAction is set to 'GoToStep' and this step succeeds.
        Use this to create conditional branching in job workflows, such as skipping cleanup steps when data processing completes successfully.

    .PARAMETER OnFailAction
        Determines job behavior when this step fails. Default 'QuitWithFailure' stops the job and reports failure.
        Use 'GoToNextStep' to continue despite failures, 'GoToStep' for error handling routines, or 'QuitWithSuccess' when failure is acceptable.
        Critical for implementing error handling and recovery procedures in automated processes.

    .PARAMETER OnFailStepId
        Identifies the step to execute when OnFailAction is 'GoToStep' and this step fails.
        Use this to implement error handling workflows, such as sending notifications or running cleanup procedures when critical steps fail.

    .PARAMETER Database
        Specifies the database context for TransactSql subsystem steps. Defaults to 'master' if not specified.
        Set this to the appropriate database where your T-SQL commands should execute, as it determines schema resolution and object access.

    .PARAMETER DatabaseUser
        Sets the database user context for executing T-SQL steps, overriding the SQL Server Agent service account permissions.
        Use this when the step needs specific database-level permissions that differ from the Agent service account's access rights.

    .PARAMETER RetryAttempts
        Sets how many times SQL Server Agent will retry this step if it fails before considering it permanently failed.
        Use this for steps that might fail due to temporary issues like network connectivity or resource contention. Defaults to 0 (no retries).

    .PARAMETER RetryInterval
        Defines the wait time in minutes between retry attempts when a step fails. Defaults to 0 (immediate retry).
        Set appropriate intervals to allow temporary issues to resolve, such as waiting for locked resources or network recovery.

    .PARAMETER OutputFileName
        Specifies a file path where the step's output will be written for logging and troubleshooting purposes.
        Use this to capture command results, error messages, or progress information for later analysis when jobs fail or need auditing.

    .PARAMETER Insert
        Inserts the new step at the specified StepId position, automatically renumbering subsequent steps and updating their references.
        Use this when adding steps to existing jobs without breaking the workflow sequence, such as inserting validation steps between existing processes.

    .PARAMETER Flag
        Controls how job step output and history are logged and stored. Multiple flags can be specified for comprehensive logging.
        Use 'AppendAllCmdExecOutputToJobHistory' to capture command output in job history, 'AppendToLogFile' for SQL Server error log entries, or 'AppendToTableLog' for database table logging.
        Essential for troubleshooting and auditing job execution, especially for steps that generate important output or error information.

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
        Specifies a SQL Server Agent proxy account to use for step execution instead of the Agent service account.
        Use this when steps need specific Windows credentials for file system access, network resources, or applications that require different security contexts.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Bypasses validation checks and overwrites existing steps with the same name or ID.
        Use this when recreating steps during development or when you need to replace existing steps without manual deletion first.

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
        [string]$Database,
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
            try {
                $Server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    Write-Message -Message "Job $j doesn't exist on $instance" -Level Warning
                } else {
                    # Create the job step object
                    try {
                        # Get the job from the server again since fields on the job object may have changed
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
                        if ($currentJob.JobSteps.Name -notcontains $StepName) {
                            $jobStep.Name = $StepName
                        } elseif (($currentJob.JobSteps.Name -contains $StepName) -and $Force) {
                            Write-Message -Message "Step $StepName already exists for job. Force is used. Removing existing step" -Level Verbose

                            # Remove the job step based on the name
                            Remove-DbaAgentJobStep -SqlInstance $instance -Job $currentJob -StepName $StepName -SqlCredential $SqlCredential -Confirm:$false

                            # Set the name job step object
                            $jobStep.Name = $StepName
                        } else {
                            Stop-Function -Message "The step name $StepName already exists for job $currentJob" -Target $instance -Continue
                        }
                    }

                    # If the step id need to be set
                    if ($StepId) {
                        # Check if the used step id is already in place
                        if ($currentJob.JobSteps.ID -notcontains $StepId) {
                            Write-Message -Message "Setting job step step id to $StepId" -Level Verbose
                            $jobStep.ID = $StepId
                        } elseif (($currentJob.JobSteps.ID -contains $StepID) -and $Insert) {
                            Write-Message -Message "Inserting step as step $StepID" -Level Verbose
                            foreach ($tStep in $currentJob.JobSteps) {
                                if ($tStep.Id -ge $Stepid) {
                                    $tStep.Id = ($tStep.ID) + 1
                                }
                                if ($tStep.OnFailureStepID -ge $StepId -and $tStep.OnFailureStepId -ne 0) {
                                    $tStep.OnFailureStepID = ($tStep.OnFailureStepID) + 1
                                }
                            }
                            $jobStep.ID = $StepId
                        } elseif (($currentJob.JobSteps.ID -contains $StepId) -and $Force) {
                            Write-Message -Message "Step ID $StepId already exists for job. Force is used. Removing existing step" -Level Verbose

                            # Remove the existing job step
                            $StepName = ($currentJob.JobSteps | Where-Object { $_.ID -eq 1 }).Name
                            Remove-DbaAgentJobStep -SqlInstance $instance -Job $currentJob -StepName $StepName -SqlCredential $SqlCredential -Confirm:$false

                            # Set the ID job step object
                            $jobStep.ID = $StepId
                        } else {
                            Stop-Function -Message "The step id $StepId already exists for job $currentJob" -Target $instance -Continue
                        }
                    } else {
                        # Get the job step count
                        $jobStep.ID = $currentJob.JobSteps.Count + 1
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

                    if ($DatabaseUser -and $Database) {
                        # Check if the username is present in the database
                        if ($Server.Databases[$Database].Users.Name -contains $DatabaseUser) {

                            Write-Message -Message "Setting job step database username to $DatabaseUser" -Level Verbose
                            $jobStep.DatabaseUserName = $DatabaseUser
                        } else {
                            Stop-Function -Message "The database user is not present in the database $Database on instance $instance." -Target $instance -Continue
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