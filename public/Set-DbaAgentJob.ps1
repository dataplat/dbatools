function Set-DbaAgentJob {
    <#
    .SYNOPSIS
        Modifies existing SQL Server Agent job properties and notification settings.

    .DESCRIPTION
        Updates various properties of SQL Server Agent jobs including job name, description, owner, enabled/disabled status, notification settings, and schedule assignments. This function lets you modify jobs without using SQL Server Management Studio, making it useful for standardizing job configurations across multiple instances or automating job maintenance tasks. You can update individual jobs or perform bulk changes across multiple jobs and SQL Server instances simultaneously.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies the name of the SQL Server Agent job to modify. Accepts wildcards and multiple job names.
        Use this to target specific jobs for configuration changes rather than modifying all jobs on an instance.

    .PARAMETER Schedule
        Attaches existing shared schedules to the job by name. Accepts multiple schedule names.
        Use this when you need to assign predefined schedules to jobs without recreating scheduling logic.

    .PARAMETER ScheduleId
        Attaches existing shared schedules to the job by their numeric ID. Accepts multiple schedule IDs.
        Use this when you know the specific schedule ID numbers and want to avoid potential name conflicts.

    .PARAMETER NewName
        Renames the job to the specified name. The new name must be unique within the SQL Server instance.
        Use this when standardizing job names across environments or fixing naming conventions.

    .PARAMETER Enabled
        Enables the job so it can be executed by SQL Server Agent schedules or manual execution.
        Use this when reactivating disabled jobs or deploying jobs that should run immediately.

    .PARAMETER Disabled
        Disables the job to prevent it from running on schedule or manual execution.
        Use this when temporarily stopping jobs during maintenance windows or permanently deactivating obsolete jobs.

    .PARAMETER Description
        Updates the job's description field with explanatory text about the job's purpose or functionality.
        Use this to document what the job does, when it should run, or special requirements for maintenance teams.

    .PARAMETER StartStepId
        Sets which job step should execute first when the job runs. Must correspond to an existing step ID within the job.
        Use this when you need to change the job's execution flow or skip initial steps during testing or maintenance.

    .PARAMETER Category
        Assigns the job to a specific job category for organizational purposes. Creates the category if it doesn't exist when used with -Force.
        Use this to group related jobs together for easier management and reporting in SQL Server Management Studio.

    .PARAMETER OwnerLogin
        Changes the job owner to the specified SQL Server login. The login must already exist on the instance.
        Use this when reassigning job ownership for security compliance or when the current owner login is being removed.

    .PARAMETER EventLogLevel
        Controls when job execution results are logged to the Windows Application Event Log. Values: Never, OnSuccess, OnFailure, Always (or 0-3).
        Use this to integrate job monitoring with Windows event log monitoring systems or reduce log noise by only logging failures.

    .PARAMETER EmailLevel
        Determines when to send email notifications about job completion. Values: Never, OnSuccess, OnFailure, Always (or 0-3).
        Must be used with EmailOperator parameter. Use this to set up automated job failure notifications to the DBA team.

    .PARAMETER NetsendLevel
        Controls when to send network messages (net send) about job completion. Values: Never, OnSuccess, OnFailure, Always (or 0-3).
        Must be used with NetsendOperator parameter. Note that net send is deprecated and rarely used in modern environments.

    .PARAMETER PageLevel
        Determines when to send pager notifications about job completion. Values: Never, OnSuccess, OnFailure, Always (or 0-3).
        Must be used with PageOperator parameter. Use this for critical jobs requiring immediate attention when they fail.

    .PARAMETER EmailOperator
        Specifies which SQL Server Agent operator receives email notifications when EmailLevel conditions are met. The operator must already exist.
        Use this to assign job failure notifications to specific DBA team members or distribution lists.

    .PARAMETER NetsendOperator
        Specifies which SQL Server Agent operator receives network messages when NetsendLevel conditions are met. The operator must already exist.
        Rarely used in modern environments due to the deprecation of the net send functionality.

    .PARAMETER PageOperator
        Specifies which SQL Server Agent operator receives pager notifications when PageLevel conditions are met. The operator must already exist.
        Use this for high-priority jobs where immediate mobile notification is required for on-call DBAs.

    .PARAMETER DeleteLevel
        Controls when the job should automatically delete itself after execution. Values: Never, OnSuccess, OnFailure, Always (or 0-3).
        Use this for one-time jobs like data migrations or temporary maintenance tasks that should clean up after completion.

    .PARAMETER Force
        Bypasses validation checks and creates missing job categories when specified with the Category parameter.
        Use this when you want to create new categories during job updates without having to pre-create them separately.

    .PARAMETER InputObject
        Accepts SQL Server Agent job objects from the pipeline, typically from Get-DbaAgentJob output.
        Use this to chain job operations together or when working with job objects retrieved from other dbatools commands.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentJob

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.Job

        Returns one modified SQL Server Agent job object per job that was successfully updated. The returned object reflects all changes applied during the modification operation.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the SQL Server Agent job
        - Category: The job category name for organizational grouping
        - OwnerLoginName: SQL Server login that owns the job
        - CurrentRunStatus: Current execution status of the job (Idle, Running, Succeeded, Failed, etc.)
        - CurrentRunRetryAttempt: Number of retry attempts for the current run
        - Enabled: Boolean indicating if the job is enabled for execution
        - LastRunDate: DateTime of the most recent job execution attempt
        - LastRunOutcome: Outcome of the last execution (Succeeded, Failed, Retry, Cancelled)
        - HasSchedule: Boolean indicating if the job has at least one schedule assigned
        - OperatorToEmail: Name of the operator to receive email notifications
        - CreateDate: DateTime when the job was created

        Additional properties available (from SMO Job object):
        - ID: Unique identifier for the job
        - JobID: The globally unique identifier (GUID) for the job
        - StartStepID: The ID of the step that executes first
        - OwnerLoginName: Login name of the job owner
        - OperatorToEmail: Email operator for notifications
        - OperatorToNetSend: Net send operator for notifications
        - OperatorToPage: Pager operator for notifications
        - EmailLevel: Email notification setting (0-3 or string equivalent)
        - NetSendLevel: Net send notification setting (0-3 or string equivalent)
        - PageLevel: Pager notification setting (0-3 or string equivalent)
        - DeleteLevel: Auto-delete setting after execution (0-3 or string equivalent)
        - DatabaseName: Default database for job steps
        - IsSystemObject: Boolean indicating if this is a system-created job
        - CreatedDate: DateTime when the job was created
        - CreateByLogin: Login that created the job
        - DateLastModified: DateTime of the most recent modification
        - ModifiedByLogin: Login that made the last modification
        - JobSteps: Collection of job steps in this job
        - Schedules: Collection of schedules assigned to this job

        All properties from the base SMO Job object are accessible using Select-Object * even though only default properties are displayed by default.

    .EXAMPLE
        PS C:\> Set-DbaAgentJob sql1 -Job Job1 -Disabled

        Changes the job to disabled

    .EXAMPLE
        PS C:\> Set-DbaAgentJob sql1 -Job Job1 -OwnerLogin user1

        Changes the owner of the job

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1 -EventLogLevel OnSuccess

        Changes the job and sets the notification to write to the Windows Application event log on success

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1 -EmailLevel OnFailure -EmailOperator dba

        Changes the job and sets the notification to send an e-mail to the e-mail operator

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1, Job2, Job3 -Enabled

        Changes multiple jobs to enabled

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1, sql2, sql3 -Job Job1, Job2, Job3 -Enabled

        Changes multiple jobs to enabled on multiple servers

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1 -Job Job1 -Description 'Just another job' -Whatif

        Doesn't Change the job but shows what would happen.

    .EXAMPLE
        PS C:\> Set-DbaAgentJob -SqlInstance sql1, sql2, sql3 -Job 'Job One' -Description 'Job One'

        Changes a job with the name "Job1" on multiple servers to have another description

    .EXAMPLE
        PS C:\> sql1, sql2, sql3 | Set-DbaAgentJob -Job Job1 -Description 'Job One'

        Changes a job with the name "Job1" on multiple servers to have another description using pipe line

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [object[]]$Schedule,
        [int[]]$ScheduleId,
        [string]$NewName,
        [switch]$Enabled,
        [switch]$Disabled,
        [string]$Description,
        [int]$StartStepId,
        [string]$Category,
        [string]$OwnerLogin,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$EventLogLevel,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$EmailLevel,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$NetsendLevel,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$PageLevel,
        [string]$EmailOperator,
        [string]$NetsendOperator,
        [string]$PageOperator,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$DeleteLevel,
        [switch]$Force,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Check of the event log level is of type string and set the integer value
        if (($EventLogLevel -notin 0, 1, 2, 3) -and ($null -ne $EventLogLevel)) {
            $EventLogLevel = switch ($EventLogLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the email level is of type string and set the integer value
        if (($EmailLevel -notin 0, 1, 2, 3) -and ($null -ne $EmailLevel)) {
            $EmailLevel = switch ($EmailLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the net send level is of type string and set the integer value
        if (($NetsendLevel -notin 0, 1, 2, 3) -and ($null -ne $NetsendLevel)) {
            $NetsendLevel = switch ($NetsendLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the page level is of type string and set the integer value
        if (($PageLevel -notin 0, 1, 2, 3) -and ($null -ne $PageLevel)) {
            $PageLevel = switch ($PageLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check of the delete level is of type string and set the integer value
        if (($DeleteLevel -notin 0, 1, 2, 3) -and ($null -ne $DeleteLevel)) {
            $DeleteLevel = switch ($DeleteLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check the e-mail operator name
        if (($EmailLevel -ge 1) -and (-not $EmailOperator)) {
            Stop-Function -Message "Please set the e-mail operator when the e-mail level parameter is set." -Target $SqlInstance
            return
        }

        # Check the e-mail level parameter
        if ($EmailOperator -and ($null -eq $EmailLevel)) {
            Stop-Function -Message "Please set the e-mail level parameter when the e-mail level operator is set." -Target $SqlInstance
            return
        }

        # Check the net send operator name
        if (($NetsendLevel -ge 1) -and (-not $NetsendOperator)) {
            Stop-Function -Message "Please set the netsend operator when the netsend level parameter is set." -Target $SqlInstance
            return
        }

        # Check the net send level parameter
        if ($NetsendOperator -and ($null -eq $NetsendLevel)) {
            Stop-Function -Message "Please set the net send level parameter when the net send level operator is set." -Target $SqlInstance
            return
        }

        # Check the page operator name
        if (($PageLevel -ge 1) -and (-not $PageOperator)) {
            Stop-Function -Message "Please set the page operator when the page level parameter is set." -Target $SqlInstance
            return
        }

        # Check the page level parameter
        if ($PageOperator -and ($null -eq $PageLevel)) {
            Stop-Function -Message "Please set the page level parameter when the page level operator is set." -Target $SqlInstance
            return
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $Job)) {
            Stop-Function -Message "You must specify a job name or pipe in results from another command" -Target $SqlInstance
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($server.JobServer.Jobs.Name -notcontains $j) {
                    Stop-Function -Message "Job $j doesn't exists on $instance" -Target $instance
                } else {
                    # Get the job
                    try {
                        $InputObject += $server.JobServer.Jobs[$j]

                        # Refresh the object
                        $InputObject.Refresh()
                    } catch {
                        Stop-Function -Message "Something went wrong retrieving the job" -Target $j -ErrorRecord $_ -Continue
                    }
                }
            }
        }

        foreach ($currentjob in $InputObject) {
            $server = $currentjob.Parent.Parent

            #region job options
            # Settings the options for the job
            if ($NewName) {
                if ($PSCmdlet.ShouldProcess($server, "Setting job name of $($currentjob.Name) to $NewName")) {
                    $currentjob.Rename($NewName)
                }
            }

            if ($Schedule) {
                # Loop through each of the schedules
                foreach ($s in $Schedule) {
                    if ($server.JobServer.SharedSchedules.Name -contains $s) {
                        # Get the schedule ID
                        $sID = $server.JobServer.SharedSchedules[$s].ID

                        # Add schedule to job
                        if ($PSCmdlet.ShouldProcess($server, "Adding schedule id $sID to job $($currentjob.Name)")) {
                            $currentjob.AddSharedSchedule($sID)
                        }
                    } else {
                        Stop-Function -Message "Schedule $s cannot be found on instance $instance" -Target $s -Continue
                    }

                }
            }

            if ($ScheduleId) {
                # Loop through each of the schedules IDs
                foreach ($sID in $ScheduleId) {
                    # Check if the schedule is
                    if ($server.JobServer.SharedSchedules.ID -contains $sID) {
                        # Add schedule to job
                        if ($PSCmdlet.ShouldProcess($server, "Adding schedule id $sID to job $($currentjob.Name)")) {
                            $currentjob.AddSharedSchedule($sID)
                        }
                    } else {
                        Stop-Function -Message "Schedule ID $sID cannot be found on instance $instance" -Target $sID -Continue
                    }
                }
            }

            if ($Enabled) {
                Write-Message -Message "Setting job to enabled" -Level Verbose
                $currentjob.IsEnabled = $true
            }

            if ($Disabled) {
                Write-Message -Message "Setting job to disabled" -Level Verbose
                $currentjob.IsEnabled = $false
            }

            if ($Description) {
                Write-Message -Message "Setting job description to $Description" -Level Verbose
                $currentjob.Description = $Description
            }

            if ($Category) {
                # Check if the job category exists
                if ($Category -notin $server.JobServer.JobCategories.Name) {
                    if ($Force) {
                        if ($PSCmdlet.ShouldProcess($instance, "Creating job category on $instance")) {
                            try {
                                # Create the category
                                New-DbaAgentJobCategory -SqlInstance $server -Category $Category

                                Write-Message -Message "Setting job category to $Category" -Level Verbose
                                $currentjob.Category = $Category
                            } catch {
                                Stop-Function -Message "Couldn't create job category $Category from $instance" -Target $instance -ErrorRecord $_
                            }
                        }
                    } else {
                        Stop-Function -Message "Job category $Category doesn't exist on $instance. Use -Force to create it." -Target $instance
                        return
                    }
                } else {
                    Write-Message -Message "Setting job category to $Category" -Level Verbose
                    $currentjob.Category = $Category
                }
            }

            if ($StartStepId) {
                # Get the job steps
                $currentjobSteps = $currentjob.JobSteps

                # Check if there are any job steps
                if ($currentjobSteps.Count -ge 1) {
                    # Check if the start step id value is one of the job steps in the job
                    if ($currentjobSteps.ID -contains $StartStepId) {
                        Write-Message -Message "Setting job start step id to $StartStepId" -Level Verbose
                        $currentjob.StartStepID = $StartStepId
                    } else {
                        Write-Message -Message "The step id is not present in job $j on instance $instance" -Warning
                    }

                } else {
                    Stop-Function -Message "There are no job steps present for job $j on instance $instance" -Target $instance -Continue
                }

            }

            if ($OwnerLogin) {
                # Check if the login name is present on the instance
                if ($server.Logins.Name -contains $OwnerLogin) {
                    Write-Message -Message "Setting job owner login name to $OwnerLogin" -Level Verbose
                    $currentjob.OwnerLoginName = $OwnerLogin
                } else {
                    Stop-Function -Message "The given owner log in name $OwnerLogin does not exist on instance $instance" -Target $instance -Continue
                }
            }

            if (Test-Bound -ParameterName EventLogLevel) {
                Write-Message -Message "Setting job event log level to $EventlogLevel" -Level Verbose
                $currentjob.EventLogLevel = $EventLogLevel
            }

            if (Test-Bound -ParameterName EmailLevel) {
                # Check if the notifiction needs to be removed
                if ($EmailLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToEmail = $null

                    # Remove the notification
                    $currentjob.EmailLevel = $EmailLevel
                } else {
                    # Check if either the operator e-mail parameter is set or the operator is set in the job
                    if ($EmailOperator -or $currentjob.OperatorToEmail) {
                        Write-Message -Message "Setting job e-mail level to $EmailLevel" -Level Verbose
                        $currentjob.EmailLevel = $EmailLevel
                    } else {
                        Stop-Function -Message "Cannot set e-mail level $EmailLevel without a valid e-mail operator name" -Target $instance -Continue
                    }
                }
            }

            if (Test-Bound -ParameterName NetsendLevel) {
                # Check if the notifiction needs to be removed
                if ($NetsendLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToNetSend = $null

                    # Remove the notification
                    $currentjob.NetSendLevel = $NetsendLevel
                } else {
                    # Check if either the operator netsend parameter is set or the operator is set in the job
                    if ($NetsendOperator -or $currentjob.OperatorToNetSend) {
                        Write-Message -Message "Setting job netsend level to $NetsendLevel" -Level Verbose
                        $currentjob.NetSendLevel = $NetsendLevel
                    } else {
                        Stop-Function -Message "Cannot set netsend level $NetsendLevel without a valid netsend operator name" -Target $instance -Continue
                    }
                }
            }

            if (Test-Bound -ParameterName PageLevel) {
                # Check if the notifiction needs to be removed
                if ($PageLevel -eq 0) {
                    # Remove the operator
                    $currentjob.OperatorToPage = $null

                    # Remove the notification
                    $currentjob.PageLevel = $PageLevel
                } else {
                    # Check if either the operator pager parameter is set or the operator is set in the job
                    if ($PageOperator -or $currentjob.OperatorToPage) {
                        Write-Message -Message "Setting job pager level to $PageLevel" -Level Verbose
                        $currentjob.PageLevel = $PageLevel
                    } else {
                        Stop-Function -Message "Cannot set page level $PageLevel without a valid netsend operator name" -Target $instance -Continue
                    }
                }
            }

            # Check the current setting of the job's email level
            if ($EmailOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $EmailOperator) {
                    Write-Message -Message "Setting job e-mail operator to $EmailOperator" -Level Verbose
                    $currentjob.OperatorToEmail = $EmailOperator
                } else {
                    Stop-Function -Message "The e-mail operator name $EmailOperator does not exist on instance $instance. Exiting.." -Target $j -Continue
                }
            }

            if ($NetsendOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $NetsendOperator) {
                    Write-Message -Message "Setting job netsend operator to $NetsendOperator" -Level Verbose
                    $currentjob.OperatorToNetSend = $NetsendOperator
                } else {
                    Stop-Function -Message "The netsend operator name $NetsendOperator does not exist on instance $instance. Exiting.." -Target $j -Continue
                }
            }

            if ($PageOperator) {
                # Check if the operator name is present
                if ($server.JobServer.Operators.Name -contains $PageOperator) {
                    Write-Message -Message "Setting job pager operator to $PageOperator" -Level Verbose
                    $currentjob.OperatorToPage = $PageOperator
                } else {
                    Stop-Function -Message "The page operator name $PageOperator does not exist on instance $instance. Exiting.." -Target $instance -Continue
                }
            }

            if (Test-Bound -ParameterName DeleteLevel) {
                Write-Message -Message "Setting job delete level to $DeleteLevel" -Level Verbose
                $currentjob.DeleteLevel = $DeleteLevel
            }
            #endregion job options

            # Execute
            if ($PSCmdlet.ShouldProcess($SqlInstance, "Changing the job $j")) {
                try {
                    Write-Message -Message "Changing the job" -Level Verbose

                    # Change the job
                    $currentjob.Alter()
                } catch {
                    Stop-Function -Message "Something went wrong changing the job" -ErrorRecord $_ -Target $instance -Continue
                }

                # Refresh the SMO - another bug in SMO? As this should not be needed...
                $currentjob.Refresh()

                Get-DbaAgentJob -SqlInstance $server -Job $currentjob.Name
            }
        }
    }

    end {
        Write-Message -Message "Finished changing job(s)" -Level Verbose
    }
}