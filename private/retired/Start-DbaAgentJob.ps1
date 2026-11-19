function Start-DbaAgentJob {
    <#
    .SYNOPSIS
        Starts SQL Server Agent jobs and optionally waits for completion

    .DESCRIPTION
        Starts one or more SQL Server Agent jobs that are currently idle. This function validates jobs are in an idle state before starting them and can optionally wait for job completion before returning results. You can start all jobs, specific jobs by name, or exclude certain jobs from execution. It also supports starting jobs at specific steps rather than from the beginning, which is useful for resuming failed jobs or testing individual job steps.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies the names of specific SQL Agent jobs to start. Accepts job names as strings and supports multiple job names in an array.
        Use this when you need to start only certain jobs instead of all jobs on the server. Job names are case-sensitive and must match exactly.

    .PARAMETER StepName
        Specifies the job step name where job execution should begin instead of starting from the first step.
        Use this to resume a failed job at a specific step or to test individual job steps without running the entire job sequence.

    .PARAMETER ExcludeJob
        Specifies job names to exclude from starting when using -AllJobs or when no specific jobs are specified.
        Use this to start all jobs except certain ones, such as excluding maintenance jobs during business hours or problematic jobs that need special handling.

    .PARAMETER AllJobs
        Starts all SQL Agent jobs that are currently in an idle state on the target instance.
        Use this switch when you need to start all available jobs, typically after server maintenance or during bulk job execution scenarios.

    .PARAMETER Wait
        Waits for each job to complete execution before returning results or proceeding to the next job.
        Use this when you need to ensure job completion before continuing your script, or when jobs have dependencies that require sequential execution.

    .PARAMETER WaitPeriod
        Sets the polling interval in seconds for checking job status when using the -Wait parameter. Defaults to 3 seconds.
        Adjust this value based on your job duration - use shorter intervals for quick jobs or longer intervals for jobs that run for hours to reduce server load.

    .PARAMETER Parallel
        Starts all specified jobs simultaneously and waits for all to complete, rather than starting and waiting for each job sequentially.
        Use this when jobs can run concurrently without conflicts to reduce total execution time. Requires the -Wait parameter to function.

    .PARAMETER SleepPeriod
        Sets the initial wait time in milliseconds after starting a job before checking its status. Defaults to 300 milliseconds.
        Increase this value if you experience issues with jobs not showing as started immediately, which can occur on heavily loaded servers.

    .PARAMETER InputObject
        Accepts SQL Agent job objects from the pipeline, typically from Get-DbaAgentJob or other dbatools functions.
        Use this when chaining dbatools commands together to start jobs that meet specific criteria, such as failed jobs or jobs with certain schedules.

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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.Job

        Returns one SQL Server Agent Job object per job started. Job objects are returned from Get-DbaAgentJob after the job execution completes (when -Wait is specified) or immediately after starting (without -Wait).

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the SQL Agent job
        - CurrentRunStatus: The current execution status of the job (Idle, Executing, etc.)
        - LastRunDate: DateTime of the most recent job execution
        - LastRunOutcome: Outcome of the last run (Succeeded, Failed, Cancelled, etc.)
        - IsEnabled: Boolean indicating if the job is enabled
        - HasSchedule: Boolean indicating if the job has schedules
        - OwnerLoginName: Login that owns the job

        Additional properties available (from SMO Agent.Job object):
        - JobSteps: Collection of job steps defined in this job
        - Schedules: Collection of schedules assigned to this job
        - Notifications: Notification settings for the job
        - Category: The job category name
        - CategoryID: The job category ID
        - CreatedDate: DateTime when the job was created
        - Description: Job description text

        Note: When using sequential processing without -Wait, jobs start but the command returns after they begin. When using -Wait (sequential or parallel), the command waits for job completion before returning results.

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
            [int]$currentStepId, [string]$currentStepName = $currentstep.Split(' ', 2)
            $currentStepName = $currentStepName.Substring(1, $currentStepName.Length - 2)
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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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