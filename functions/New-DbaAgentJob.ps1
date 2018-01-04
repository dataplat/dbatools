#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function New-DbaAgentJob {
    <#
.SYNOPSIS
New-DbaAgentJob creates a new job

.DESCRIPTION
New-DbaAgentJob makes is possible to create a job in the SQL Server Agent.
It returns an array of the job(s) created

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Job
The name of the job. The name must be unique and cannot contain the percent (%) character.

.PARAMETER Schedule
Schedule to attach to job. This can be more than one schedule.

.PARAMETER ScheduleId
Schedule ID to attach to job. This can be more than one schedule ID.

.PARAMETER Disabled
Sets the status of the job to disabled. By default a job is enabled.

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

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Agent, Job, Job Step

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/New-DbaAgentJob

.EXAMPLE
New-DbaAgentJob -SqlInstance sql1 -Job 'Job One' -Description 'Just another job'
Creates a job with the name "Job1" and a small description

.EXAMPLE
New-DbaAgentJob -SqlInstance sql1 -Job 'Job One' -Disabled
Creates the job but sets it to disabled

.EXAMPLE
New-DbaAgentJob -SqlInstance sql1 -Job 'Job One' -EventLogLevel OnSuccess
Creates the job and sets the notification to write to the Windows Application event log on success

.EXAMPLE
New-DbaAgentJob -SqlInstance SSTAD-PC -Job 'Job One' -EmailLevel OnFailure -EmailOperator dba
Creates the job and sets the notification to send an e-mail to the e-mail operator

.EXAMPLE
New-DbaAgentJob -SqlInstance sql1 -Job 'Job One' -Description 'Just another job' -Whatif
Doesn't create the job but shows what would happen.

.EXAMPLE
New-DbaAgentJob -SqlInstance sql1, sql2, sql3 -Job 'Job One'
Creates a job with the name "Job One" on multiple servers

.EXAMPLE
"sql1", "sql2", "sql3" | New-DbaAgentJob -Job 'Job One'
Creates a job with the name "Job One" on multiple servers using the pipe line
#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Job,
        [object[]]$Schedule,
        [int[]]$ScheduleId,
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
        [Parameter()]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$PageLevel,
        [string]$EmailOperator,
        [string]$NetsendOperator,
        [string]$PageOperator,
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$DeleteLevel,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {

        # Check of the event log level is of type string and set the integer value
        if ($EventLogLevel -notin 1, 2, 3) {
            $EventLogLevel = switch ($EventLogLevel) {
                "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 }
                default { 0 }
            }
        }

        # Check of the email level is of type string and set the integer value
        if ($EmailLevel -notin 1, 2, 3) {
            $EmailLevel = switch ($EmailLevel) {
                "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 }
                default { 0 }
            }
        }

        # Check of the net send level is of type string and set the integer value
        if ($NetsendLevel -notin 1, 2, 3) {
            $NetsendLevel = switch ($NetsendLevel) {
                "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 }
                default { 0 }
            }
        }

        # Check of the page level is of type string and set the integer value
        if ($PageLevel -notin 1, 2, 3) {
            $PageLevel = switch ($PageLevel) {
                "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 }
                default { 0 }
            }
        }

        # Check of the delete level is of type string and set the integer value
        if ($DeleteLevel -notin 1, 2, 3) {
            $DeleteLevel = switch ($DeleteLevel) {
                "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 }
                default { 0 }
            }
        }

        # Check the e-mail operator name
        if (($EmailLevel -ge 1) -and (-not $EmailOperator)) {
            Stop-Function -Message "Please set the e-mail operator when the e-mail level parameter is set." -Target $sqlinstance
            return
        }

        # Check the e-mail operator name
        if (($NetsendLevel -ge 1) -and (-not $NetsendOperator)) {
            Stop-Function -Message "Please set the netsend operator when the netsend level parameter is set." -Target $sqlinstance
            return
        }

        # Check the e-mail operator name
        if (($PageLevel -ge 1) -and (-not $PageOperator)) {
            Stop-Function -Message "Please set the page operator when the page level parameter is set." -Target $sqlinstance
            return
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Check if the job already exists
            if (-not $Force -and ($server.JobServer.Jobs.Name -contains $Job)) {
                Stop-Function -Message "Job $Job already exists on $instance" -Target $instance -Continue
            }
            elseif ($Force -and ($server.JobServer.Jobs.Name -contains $Job)) {
                Write-Message -Message "Job $Job already exists on $instance. Removing.." -Level Verbose

                if ($PSCmdlet.ShouldProcess($instance, "Removing the job $Job on $instance")) {
                    try {
                        Remove-DbaAgentJob -SqlInstance $instance -Job $Job -EnableException
                    }
                    catch {
                        Stop-Function -Message "Couldn't remove job $Job from $instance" -Target $instance -Continue -ErrorRecord $_
                    }
                }

            }

            if ($PSCmdlet.ShouldProcess($instance, "Creating the job on $instance")) {
                # Create the job object
                try {
                    $currentjob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job($server.JobServer, $Job)
                }
                catch {
                    Stop-Function -Message "Something went wrong creating the job. `n" -Target $Job -Continue -ErrorRecord $_
                }

                #region job options
                # Settings the options for the job
                if ($Disabled) {
                    Write-Message -Message "Setting job to disabled" -Level Verbose
                    $currentjob.IsEnabled = $false
                }
                else {
                    Write-Message -Message "Setting job to enabled" -Level Verbose
                    $currentjob.IsEnabled = $true
                }

                if ($Description.Length -ge 1) {
                    Write-Message -Message "Setting job description" -Level Verbose
                    $currentjob.Description = $Description
                }

                if ($StartStepId -ge 1) {
                    Write-Message -Message "Setting job start step id" -Level Verbose
                    $currentjob.StartStepID = $StartStepId
                }

                if ($Category.Length -ge 1) {
                    # Check if the job category exists
                    if ($Category -notin $server.JobServer.JobCategories.Name) {
                        if ($Force) {
                            if ($PSCmdlet.ShouldProcess($instance, "Creating job category on $instance")) {
                                try {
                                    # Create the category
                                    New-DbaAgentJobCategory -SqlInstance $instance -Category $Category
                                }
                                catch {
                                    Stop-Function -Message "Couldn't create job category $Category from $instance" -Target $instance -Continue -ErrorRecord $_
                                }
                            }
                        }
                        else {
                            Stop-Function -Message "Job category $Category doesn't exist on $instance. Use -Force to create it." -Target $instance
                            return
                        }
                    }
                    else {
                        Write-Message -Message "Setting job category" -Level Verbose
                        $currentjob.Category = $Category
                    }
                }

                if ($OwnerLogin.Length -ge 1) {
                    # Check if the login name is present on the instance
                    if ($server.Logins.Name -contains $OwnerLogin) {
                        Write-Message -Message "Setting job owner login name to $OwnerLogin" -Level Verbose
                        $currentjob.OwnerLoginName = $OwnerLogin
                    }
                    else {
                        Stop-Function -Message "The owner $OwnerLogin does not exist on instance $instance" -Target $Job -Continue
                    }
                }

                if ($EventLogLevel -ge 0) {
                    Write-Message -Message "Setting job event log level" -Level Verbose
                    $currentjob.EventLogLevel = $EventLogLevel
                }

                if ($EmailOperator) {
                    if ($EmailLevel -ge 1) {
                        # Check if the operator name is present
                        if ($server.JobServer.Operators.Name -contains $EmailOperator) {
                            Write-Message -Message "Setting job e-mail level" -Level Verbose
                            $currentjob.EmailLevel = $EmailLevel

                            Write-Message -Message "Setting job e-mail operator" -Level Verbose
                            $currentjob.OperatorToEmail = $EmailOperator
                        }
                        else {
                            Stop-Function -Message "The e-mail operator name $EmailOperator does not exist on instance $instance. Exiting.." -Target $Job -Continue
                        }
                    }
                    else {
                        Stop-Function -Message "Invalid combination of e-mail operator name $EmailOperator and email level $EmailLevel. Not setting the notification." -Target $Job -Continue
                    }
                }

                if ($NetsendOperator) {
                    if ($NetsendLevel -ge 1) {
                        # Check if the operator name is present
                        if ($server.JobServer.Operators.Name -contains $NetsendOperator) {
                            Write-Message -Message "Setting job netsend level" -Level Verbose
                            $currentjob.NetSendLevel = $NetsendLevel

                            Write-Message -Message "Setting job netsend operator" -Level Verbose
                            $currentjob.OperatorToNetSend = $NetsendOperator
                        }
                        else {
                            Stop-Function -Message "The netsend operator name $NetsendOperator does not exist on instance $instance. Exiting.." -Target $Job -Continue
                        }
                    }
                    else {
                        Write-Message -Message "Invalid combination of netsend operator name $NetsendOperator and netsend level $NetsendLevel. Not setting the notification."
                    }
                }

                if ($PageOperator) {
                    if ($PageLevel -ge 1) {
                        # Check if the operator name is present
                        if ($server.JobServer.Operators.Name -contains $PageOperator) {
                            Write-Message -Message "Setting job pager level" -Level Verbose
                            $currentjob.PageLevel = $PageLevel

                            Write-Message -Message "Setting job pager operator" -Level Verbose
                            $currentjob.OperatorToPage = $PageOperator
                        }
                        else {
                            Stop-Function -Message "The page operator name $PageOperator does not exist on instance $instance. Exiting.." -Target $Job -Continue
                        }
                    }
                    else {
                        Write-Message -Message "Invalid combination of page operator name $PageOperator and page level $PageLevel. Not setting the notification." -Level Warning
                    }
                }

                if ($DeleteLevel -ge 0) {
                    Write-Message -Message "Setting job delete level" -Level Verbose
                    $currentjob.DeleteLevel = $DeleteLevel
                }
                #endregion job options

                try {
                    Write-Message -Message "Creating the job" -Level Verbose

                    # Create the job
                    $currentjob.Create()

                    Write-Message -Message "Job created with UID $($currentjob.JobID)" -Level Verbose

                    # Make sure the target is set for the job
                    Write-Message -Message "Applying the target (local) to job $Job" -Level Verbose
                    $currentjob.ApplyToTargetServer("(local)")

                    # If a schedule needs to be attached
                    if ($Schedule) {
                        Set-DbaAgentJob -SqlInstance $instance -Job $currentjob -Schedule $Schedule -SqlCredential $SqlCredential
                    }

                    if ($ScheduleId) {
                        Set-DbaAgentJob -SqlInstance $instance -Job $currentjob -ScheduleId $ScheduleId -SqlCredential $SqlCredential
                    }
                }
                catch {
                    Stop-Function -Message "Something went wrong creating the job" -Target $currentjob -ErrorRecord $_ -Continue
                }
            }

            # Return the job
            return $currentjob
        }
    }

    end {
        if (Test-FunctionInterrupt) { return }
        Write-Message -Message "Finished creating job(s)." -Level Verbose
    }

}
