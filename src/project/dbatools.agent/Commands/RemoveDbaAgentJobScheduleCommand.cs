#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoAgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Detaches schedules from SQL Server Agent jobs.
/// </summary>
/// <remarks>
/// The instance connection, the job/schedule resolution, the confirmation gate, the Drop (detach), and the
/// result-object shaping all run the original dbatools PowerShell body inside the dbatools module scope
/// rather than being reimplemented in C#, so the engine decides the observable details.
///
/// The function collects every job across the whole pipeline in its begin/process blocks and only detaches
/// in end, to avoid "Collection was modified" when piped directly from Get-DbaAgentJob. The accumulator
/// ($jobs) is pipeline-spanning state a per-record hop scope cannot hold, so it lives in C#: begin seeds an
/// empty list, each process record contributes its jobs (the SqlInstance/Job lookups plus the bound
/// InputObject) by EMITTING them for the C# to accumulate, and the end hop receives the full list to
/// detach. The process Stop-Functions all use -Continue, so gathering never sets the function-scope
/// interrupt; the end block's no-Continue Stop-Function (a failed detach) sets it but nothing reads
/// Test-FunctionInterrupt and the end is a single invocation, so it is inert here.
///
/// The end hop streams: it emits a result object per schedule as each Drop runs, before a later Drop may
/// throw under -EnableException, so buffering would hide detaches that actually happened (DEF-001). The
/// process hop is buffered - it is read-only gathering.
///
/// This cmdlet supplies the real ShouldProcess runtime to the end hop (ConfirmImpact High, no -Force).
/// Surface pinned by migration/baselines/Remove-DbaAgentJobSchedule.json.
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaAgentJobSchedule", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaAgentJobScheduleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name of the SQL Agent job(s) from which to detach the schedule.</summary>
    [Parameter(Position = 2)]
    public string[]? Job { get; set; }

    /// <summary>The name of the schedule(s) to detach from the job.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [ValidateNotNullOrEmpty]
    public string[] Schedule { get; set; } = null!;

    /// <summary>Job objects piped in from Get-DbaAgentJob.</summary>
    [Parameter(Position = 4, ValueFromPipeline = true)]
    public SmoAgentJob[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // The pipeline-spanning accumulator: the source's begin "$jobs = @()", filled across process records,
    // drained in end.
    private List<PSObject> _jobs = null!;

    protected override void BeginProcessing()
    {
        _jobs = new List<PSObject>();
    }

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
                return;
            }
            if (item is not null)
            {
                _jobs.Add(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Job, InputObject, EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("Job"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
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
        }, EndScript,
            _jobs.ToArray(), Schedule, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block. The source appends the resolved jobs to $jobs; here it EMITS them and the C#
    // accumulates, because the accumulator must span the pipeline. Apart from that emit-instead-of-append,
    // the block is the source VERBATIM save Test-Bound -ParameterName Job -> the carried $__boundJob flag
    // and -FunctionName Remove-DbaAgentJobSchedule on the direct Stop-Function sites.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Job, $InputObject, $EnableException, $__boundJob, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Job, [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject, $EnableException, $__boundJob)
    foreach ($instance in $SqlInstance) {
        if (-not ($__boundJob)) {
            Stop-Function -Message "Parameter -Job is required when using -SqlInstance" -Target $instance -Continue -FunctionName Remove-DbaAgentJobSchedule
        }

        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaAgentJobSchedule
        }

        foreach ($jobName in $Job) {
            if ($server.JobServer.Jobs.Name -notcontains $jobName) {
                Stop-Function -Message "Job '$jobName' does not exist on $instance" -Target $instance -Continue -FunctionName Remove-DbaAgentJobSchedule
            }
            $server.JobServer.Jobs[$jobName]
        }
    }

    foreach ($jobObject in $InputObject) {
        $jobObject
    }
} $SqlInstance $SqlCredential $Job $InputObject $EnableException $__boundJob @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess and
    // -FunctionName Remove-DbaAgentJobSchedule on the direct Stop-Function/Write-Message sites. $jobs is the
    // accumulated list. EnableException is bound so Stop-Function's scope-walking default inherits it.
    private const string EndScript = """
param($jobs, $Schedule, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($jobs, [string[]]$Schedule, $EnableException, $__realCmdlet)
    # We process in the end block to prevent "Collection was modified; enumeration operation may not execute."
    # if job objects are directly piped from Get-DbaAgentJob.
    foreach ($jobObject in $jobs) {
        $server = $jobObject.Parent.Parent

        foreach ($scheduleName in $Schedule) {
            $jobSchedules = @($jobObject.JobSchedules | Where-Object { $_.Name -eq $scheduleName })

            if (-not $jobSchedules) {
                Stop-Function -Message "Schedule '$scheduleName' is not attached to job '$($jobObject.Name)' on $($server.Name)" -Target $jobObject -Continue -FunctionName Remove-DbaAgentJobSchedule
            }

            foreach ($jobSchedule in $jobSchedules) {
                $output = [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Job          = $jobObject.Name
                    Schedule     = $scheduleName
                    ScheduleId   = $jobSchedule.Id
                    ScheduleUid  = $jobSchedule.ScheduleUid
                    Status       = $null
                    IsDetached   = $false
                }

                if ($__realCmdlet.ShouldProcess($server, "Detaching schedule '$scheduleName' from job '$($jobObject.Name)'")) {
                    try {
                        Write-Message -Level Verbose -Message "Detaching schedule '$scheduleName' from job '$($jobObject.Name)' on $($server.Name)" -FunctionName Remove-DbaAgentJobSchedule -ModuleName "dbatools"
                        $jobSchedule.Drop($true)
                        $output.Status = "Detached"
                        $output.IsDetached = $true
                    } catch {
                        Stop-Function -Message "Failed to detach schedule '$scheduleName' from job '$($jobObject.Name)' on $($server.Name)" -ErrorRecord $_ -Target $jobObject -FunctionName Remove-DbaAgentJobSchedule
                        $output.Status = (Get-ErrorMessage -Record $_)
                    }
                }

                $output
            }
        }
    }
} $jobs $Schedule $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
