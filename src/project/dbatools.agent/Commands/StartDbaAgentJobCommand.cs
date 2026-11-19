#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoAgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Starts SQL Server Agent jobs, optionally waiting for completion.
/// </summary>
/// <remarks>
/// The instance connection, the job collection/filtering, the Start call, the idle/completion polling
/// (including the serial and parallel -Wait paths), and the output all run the original dbatools PowerShell
/// body inside the dbatools module scope rather than being reimplemented in C#, so the engine decides the
/// observable details.
///
/// The two parameter sets (Instance vs Object) are mutually exclusive: with -SqlInstance the body gathers
/// the server's jobs into $InputObject and filters, then starts each; with piped job objects the pipeline
/// rebinds $InputObject per record. Neither carries state across records, so a single per-record hop
/// reproduces both. The begin block's only content is the $waitBlock scriptblock literal; it is
/// self-contained (all its variables are its own parameters or locals, with no closure over the function
/// scope), so it is folded into the top of the process hop rather than carried between hops.
///
/// Output streams as it is produced. The Test-Bound "was this parameter bound" guards become
/// $__bound.ContainsKey lookups on this cmdlet's own bound parameters (inside the hop the inner
/// $PSBoundParameters would show every parameter as bound). This cmdlet supplies the real ShouldProcess
/// runtime to the hop (ConfirmImpact Medium, no -Force). Surface pinned by
/// migration/baselines/Start-DbaAgentJob.json.
/// </remarks>
[Cmdlet(VerbsLifecycle.Start, "DbaAgentJob", SupportsShouldProcess = true, DefaultParameterSetName = "Default", ConfirmImpact = ConfirmImpact.Medium)]
public sealed class StartDbaAgentJobCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Instance")]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only start these named jobs.</summary>
    [Parameter]
    public string[]? Job { get; set; }

    /// <summary>Start the job at this step name.</summary>
    [Parameter]
    public string? StepName { get; set; }

    /// <summary>Start all jobs except these named ones.</summary>
    [Parameter]
    public string[]? ExcludeJob { get; set; }

    /// <summary>Agent job objects piped in from Get-DbaAgentJob.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Object")]
    public SmoAgentJob[]? InputObject { get; set; }

    /// <summary>Start all jobs on the instance.</summary>
    [Parameter]
    public SwitchParameter AllJobs { get; set; }

    /// <summary>Wait for each job to finish before returning.</summary>
    [Parameter]
    public SwitchParameter Wait { get; set; }

    /// <summary>Start all jobs and wait for them all in parallel.</summary>
    [Parameter]
    public SwitchParameter Parallel { get; set; }

    /// <summary>Seconds to wait between status polls when -Wait is used.</summary>
    [Parameter]
    public int WaitPeriod { get; set; } = 3;

    /// <summary>Milliseconds to sleep between refreshes.</summary>
    [Parameter]
    public int SleepPeriod { get; set; } = 300;

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (all sets), which the
    // inherited [Parameter] (no ParameterSetName) reflects as __AllParameterSets, matching the baseline; no
    // per-set override is needed here (the source likewise names sets only on SqlInstance/InputObject).

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, BodyScript,
            SqlInstance, SqlCredential, Job, StepName, ExcludeJob, InputObject, AllJobs.ToBool(), Wait.ToBool(),
            Parallel.ToBool(), WaitPeriod, SleepPeriod, EnableException.ToBool(),
            new Hashtable(MyInvocation.BoundParameters), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess, the
    // three Test-Bound -Not sites -> negated $__bound.ContainsKey lookups, and -FunctionName Start-DbaAgentJob
    // on the direct Stop-Function/Write-Message sites (including the ones inside the folded $waitBlock). The
    // begin block's $waitBlock scriptblock (self-contained, no closure) is prepended to the process hop.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Job, $StepName, $ExcludeJob, $InputObject, $AllJobs, $Wait, $Parallel, $WaitPeriod, $SleepPeriod, $EnableException, $__bound, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Job, [string]$StepName, [string[]]$ExcludeJob, [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject, $AllJobs, $Wait, $Parallel, [int]$WaitPeriod, [int]$SleepPeriod, $EnableException, $__bound, $__realCmdlet)
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
    if ((-not $__bound.ContainsKey('AllJobs')) -and (-not $__bound.ContainsKey('Job')) -and (-not $__bound.ContainsKey('InputObject'))) {
        Stop-Function -Message "Please use one of the job parameters, either -Job or -AllJobs. Or pipe in a list of jobs." -FunctionName Start-DbaAgentJob
        return
    }

    if ((-not $Wait) -and ($Parallel)) {
        Stop-Function -Message "Please use the -Wait(:`$true) switch when using -Parallel(:`$true)." -FunctionName Start-DbaAgentJob
        return
    }

    # Loop through each of the instances and store agent jobs
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Start-DbaAgentJob
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
            Stop-Function -Message "$currentjob on $server is not idle ($status)" -Target $currentjob -Continue -FunctionName Start-DbaAgentJob
        }

        If ($__realCmdlet.ShouldProcess($server, "Starting job $currentjob")) {
            # Start the job
            $lastrun = $currentjob.LastRunDate
            Write-Message -Level Verbose -Message "Last run date was $lastrun" -FunctionName Start-DbaAgentJob -ModuleName "dbatools"
            if ($StepName) {
                if ($currentjob.JobSteps.Name -contains $StepName) {
                    Write-Message -Level Verbose -Message "Starting job [$currentjob] at step [$StepName]" -FunctionName Start-DbaAgentJob -ModuleName "dbatools"
                    $null = $currentjob.Start($StepName)
                } else {
                    Write-Message -Level Verbose -Message "Job [$currentjob] does not contain step [$StepName]" -FunctionName Start-DbaAgentJob -ModuleName "dbatools"
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
                Write-Message -Level Verbose -Message "Job $($currentjob.Name) status is $($currentjob.CurrentRunStatus)" -FunctionName Start-DbaAgentJob -ModuleName "dbatools"
                Write-Message -Level Verbose -Message "Job $($currentjob.Name) last run date is $($currentjob.LastRunDate)" -FunctionName Start-DbaAgentJob -ModuleName "dbatools"

                Write-Message -Level Verbose -Message "Sleeping for $SleepPeriod ms and refreshing" -FunctionName Start-DbaAgentJob -ModuleName "dbatools"
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
} $SqlInstance $SqlCredential $Job $StepName $ExcludeJob $InputObject $AllJobs $Wait $Parallel $WaitPeriod $SleepPeriod $EnableException $__bound $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
