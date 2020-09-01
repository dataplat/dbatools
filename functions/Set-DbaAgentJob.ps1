function Set-DbaAgentJob {
    <#
    .SYNOPSIS
        Set-DbaAgentJob updates a job.

    .DESCRIPTION
        Set-DbaAgentJob updates a job in the SQL Server Agent with parameters supplied.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job.

    .PARAMETER Schedule
        Schedule to attach to job. This can be more than one schedule.

    .PARAMETER ScheduleId
        Schedule ID to attach to job. This can be more than one schedule ID.

    .PARAMETER NewName
        The new name for the job.

    .PARAMETER Enabled
        Enabled the job.

    .PARAMETER Disabled
        Disabled the job

    .PARAMETER Description
        The description of the job.

    .PARAMETER StartStepId
        The identification number of the first step to execute for the job.

    .PARAMETER Category
        The category of the job.

    .PARAMETER OwnerLogin
        The name of the login that owns the job.

    .PARAMETER EventLogLevel
        Specifies when to place an entry in the Microsoft Windows application log for this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER EmailLevel
        Specifies when to send an e-mail upon the completion of this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER NetsendLevel
        Specifies when to send a network message upon the completion of this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER PageLevel
        Specifies when to send a page upon the completion of this job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER EmailOperator
        The e-mail name of the operator to whom the e-mail is sent when EmailLevel is reached.

    .PARAMETER NetsendOperator
        The name of the operator to whom the network message is sent.

    .PARAMETER PageOperator
        The name of the operator to whom a page is sent.

    .PARAMETER DeleteLevel
        Specifies when to delete the job.
        Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
        The text value van either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.

    .PARAMETER InputObject
        Enables piping job objects

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

        # Check the e-mail operator name
        if (($NetsendLevel -ge 1) -and (-not $NetsendOperator)) {
            Stop-Function -Message "Please set the netsend operator when the netsend level parameter is set." -Target $SqlInstance
            return
        }

        # Check the e-mail operator name
        if (($PageLevel -ge 1) -and (-not $PageOperator)) {
            Stop-Function -Message "Please set the page operator when the page level parameter is set." -Target $SqlInstance
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
                Write-Message -Message "Setting job name to $NewName" -Level Verbose
                $currentjob.Rename($NewName)
            }

            if ($Schedule) {
                # Loop through each of the schedules
                foreach ($s in $Schedule) {
                    if ($server.JobServer.SharedSchedules.Name -contains $s) {
                        # Get the schedule ID
                        $sID = $server.JobServer.SharedSchedules[$s].ID

                        # Add schedule to job
                        Write-Message -Message "Adding schedule id $sID to job" -Level Verbose
                        $currentjob.AddSharedSchedule($sID)
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
                        Write-Message -Message "Adding schedule id $sID to job" -Level Verbose
                        $currentjob.AddSharedSchedule($sID)

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
                                New-DbaAgentJobCategory -SqlInstance $instance -Category $Category

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
                Get-DbaAgentJob -SqlInstance $server | Where-Object Name -eq $currentjob.name
            }
        }
    }

    end {
        Write-Message -Message "Finished changing job(s)" -Level Verbose
    }
}