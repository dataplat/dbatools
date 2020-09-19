function Start-DbaAgentJob {
    <#
    .SYNOPSIS
        Starts a running SQL Server Agent Job.

    .DESCRIPTION
        This command starts a job then returns connected SMO object for SQL Agent Job information for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The job(s) to process - this list is auto-populated from the server. If unspecified, all jobs will be processed.

    .PARAMETER StepName
        The step name to start the job at, will default to the step configured by the job.

    .PARAMETER ExcludeJob
        The job(s) to exclude - this list is auto-populated from the server.

    .PARAMETER AllJobs
        Retrieve all the jobs

    .PARAMETER Wait
        Wait for output until the job has started

    .PARAMETER WaitPeriod
        Wait period in seconds to use when -Wait is used

    .PARAMETER Parallel
        Works in conjunction with the Wait switch.  Be default, when passing the Wait switch, each job is started one at a time and waits for completion
        before starting the next job.  The Parallel switch will change the behavior to start all jobs at once, and wait for all jobs to complete .

    .PARAMETER SleepPeriod
        Period in milliseconds to wait after a job has started

    .PARAMETER InputObject
        Internal parameter that enables piping

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Job, Agent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Start-DbaAgentJob

    .EXAMPLE
        PS C:\> Start-DbaAgentJob -SqlInstance localhost

        Starts all running SQL Agent Jobs on the local SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 -Job cdc.DBWithCDC_capture | Start-DbaAgentJob

        Starts the cdc.DBWithCDC_capture SQL Agent Job on sql2016

    .EXAMPLE
        PS C:\> Start-DbaAgentJob -SqlInstance sql2016 -Job cdc.DBWithCDC_capture

        Starts the cdc.DBWithCDC_capture SQL Agent Job on sql2016

    .EXAMPLE
        PS C:\> $servers | Find-DbaAgentJob -IsFailed | Start-DbaAgentJob

        Restarts all failed jobs on all servers in the $servers collection

    .EXAMPLE
        PS C:\> Start-DbaAgentJob -SqlInstance sql2016 -AllJobs

        Start all the jobs

    .EXAMPLE
        PS C:\> Start-DbaAgentJob -SqlInstance sql2016 -Job @('Job1', 'Job2', 'Job3') -Wait

        This is a serialized approach to submitting jobs and waiting for each job to continue the next.
        Starts Job1, waits for completion of Job1
        Starts Job2, waits for completion of Job2
        Starts Job3, Waits for completion of Job3

    .EXAMPLE
        PS C:\> Start-DbaAgentJob -SqlInstance sql2016 -Job @('Job1', 'Job2', 'Job3') -Wait -Parallel

        This is a parallel approach to submitting all jobs and waiting for them all to complete.
        Starts Job1, starts Job2, starts Job3 and waits for completion of Job1, Job2, and Job3.

    .EXAMPLE
        PS C:\> Start-DbaAgentJob -SqlInstance sql2016 -Job JobWith5Steps -StepName Step4

        Starts the JobWith5Steps SQL Agent Job at step Step4.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ParameterSetName = "Instance")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Job,
        [string]$StepName,
        [string[]]$ExcludeJob,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Object")]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$AllJobs,
        [switch]$Wait,
        [switch]$Parallel,
        [int]$WaitPeriod = 3,
        [int]$SleepPeriod = 300,
        [switch]$EnableException
    )
    begin {
        [ScriptBlock]$waitBlock = {
            param(
                [Microsoft.SqlServer.Management.Smo.Agent.Job]$currentjob,
                [switch]$Wait,
                [int]$WaitPeriod
            )
            [string]$server = $currentjob.Parent.Parent.Name
            [string]$currentStep = $currentjob.CurrentRunStep
            [int]$currentStepId = $currentstep.Split('()')[0].Trim()
            [string]$currentStepName = $currentstep.Split('()')[1]
            [string]$currentRunStatus = $currentjob.CurrentRunStatus
            [int]$jobStepsCount = $currentjob.JobSteps.Count
            [int]$currentStepRetryAttempts = $currentjob.CurrentRunRetryAttempt
            [int]$currentStepRetries = $currentjob.JobSteps[$currentStepName].RetryAttempts
            Write-Message -Level Verbose -Message "Server: $server - $currentjob is $currentRunStatus, currently on Job Step '$currentStepName' ($currentStepId of $jobStepsCount), and has tried $currentStepRetryAttempts of $currentStepRetries retry attempts"
            if (($Wait) -and ($WaitPeriod) ) { Start-Sleep -Seconds $WaitPeriod }
            $currentjob.Refresh()
        }
    }
    process {
        if ((Test-Bound -not -ParameterName AllJobs) -and (Test-Bound -not -ParameterName Job) -and (Test-Bound -not -ParameterName InputObject)) {
            Stop-Function -Message "Please use one of the job parameters, either -Job or -AllJobs. Or pipe in a list of jobs."
            return
        }

        if ((-not $Wait) -and ($Parallel)) {
            Stop-Function -Message "Please use the -Wait(:`$true) switch when using -Parallel(:`$true)."
            return
        }

        # Loop through each of the instances and store agent jobs
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Check if all the jobs need to included
            if ($AllJobs) {
                $InputObject += $server.JobServer.Jobs
            }

            # If a specific job needs to be added
            if (-not $AllJobs -and $Job) {
                $InputObject += $server.JobServer.Jobs | Where-Object Name -In $Job
            }

            # If a job needs to be excluded
            if ($ExcludeJob) {
                $InputObject += $InputObject | Where-Object Name -NotIn $ExcludeJob
            }
        }

        # Loop through each of the jobs and start them.  Optionally wait for each job to finish before continuing to the next.
        foreach ($currentjob in $InputObject) {
            $server = $currentjob.Parent.Parent
            $status = $currentjob.CurrentRunStatus

            if ($status -ne 'Idle') {
                Stop-Function -Message "$currentjob on $server is not idle ($status)" -Target $currentjob -Continue
            }

            If ($Pscmdlet.ShouldProcess($server, "Starting job $currentjob")) {
                # Start the job
                $lastrun = $currentjob.LastRunDate
                Write-Message -Level Verbose -Message "Last run date was $lastrun"
                if ($StepName) {
                    if ($currentjob.JobSteps.Name -contains $StepName) {
                        Write-Message -Level Verbose -Message "Starting job [$currentjob] at step [$StepName]"
                        $null = $currentjob.Start($StepName)
                    } else {
                        Write-Message -Level Verbose -Message "Job [$currentjob] does not contain step [$StepName]"
                        continue
                    }
                } else {
                    $null = $currentjob.Start()
                }


                # Wait and refresh so that it has a chance to change status
                Start-Sleep -Milliseconds $SleepPeriod
                $currentjob.Refresh()

                $i = 0
                # Check if the status is Idle
                while (($currentjob.CurrentRunStatus -eq 'Idle' -and $i++ -lt 60)) {
                    Write-Message -Level Verbose -Message "Job $($currentjob.Name) status is $($currentjob.CurrentRunStatus)"
                    Write-Message -Level Verbose -Message "Job $($currentjob.Name) last run date is $($currentjob.LastRunDate)"

                    Write-Message -Level Verbose -Message "Sleeping for $SleepPeriod ms and refreshing"
                    Start-Sleep -Milliseconds $SleepPeriod
                    $currentjob.Refresh()

                    # If it failed fast, speed up output
                    if ($lastrun -ne $currentjob.LastRunDate) {
                        $i = 600
                    }
                }

                if (($Wait) -and (-not $Parallel)) {
                    # Wait for each job in a serialized fashion.
                    while ($currentjob.CurrentRunStatus -ne 'Idle') {
                        Invoke-Command -ScriptBlock $waitBlock -ArgumentList @($currentjob, $true, $WaitPeriod)
                    }
                    Get-DbaAgentJob -SqlInstance $server -Job $($currentjob.Name)
                } elseif (-not $Parallel) {
                    Get-DbaAgentJob -SqlInstance $server -Job $($currentjob.Name)
                }
            }
        }

        # Wait for each job to be done in parallel
        if ($Parallel) {
            while ($InputObject.CurrentRunStatus -contains 'Executing') {
                foreach ($currentjob in $InputObject) {
                    Invoke-Command -ScriptBlock $waitBlock -ArgumentList @($currentjob)
                }
                Start-Sleep -Seconds $WaitPeriod
            }
            Get-DbaAgentJob -SqlInstance $($InputObject.Parent.Parent | Select-Object -Unique) -Job $($InputObject.Name | Select-Object -Unique);
        }
    }
}