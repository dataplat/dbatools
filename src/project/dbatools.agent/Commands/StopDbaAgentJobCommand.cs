#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using SmoAgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Stops running SQL Server Agent jobs.
/// </summary>
/// <remarks>
/// The instance connection, the job collection/filtering, the Stop call, the idle-wait polling, and the
/// output all run the original dbatools PowerShell body inside the dbatools module scope rather than
/// being reimplemented in C#, so the engine decides the observable details.
///
/// The two parameter sets (Instance vs Object) are mutually exclusive: with -SqlInstance the body
/// gathers the server's jobs into $InputObject and filters by Job/ExcludeJob, then stops each; with piped
/// job objects the pipeline rebinds $InputObject per record. Neither carries state across records, so a
/// single per-record hop reproduces both.
///
/// Output streams as it is produced. A record can hold several jobs, and each stopped job is emitted
/// before a later one may fail under -EnableException; buffering would hide jobs that were actually
/// stopped.
///
/// This cmdlet supplies the real ShouldProcess runtime to the hop (ConfirmImpact Medium, no -Force).
/// Surface pinned by migration/baselines/Stop-DbaAgentJob.json.
/// </remarks>
[Cmdlet(VerbsLifecycle.Stop, "DbaAgentJob", SupportsShouldProcess = true, DefaultParameterSetName = "Default", ConfirmImpact = ConfirmImpact.Medium)]
public sealed class StopDbaAgentJobCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Instance")]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only stop these named jobs.</summary>
    [Parameter]
    public string[]? Job { get; set; }

    /// <summary>Stop all jobs except these named ones.</summary>
    [Parameter]
    public string[]? ExcludeJob { get; set; }

    /// <summary>Agent job objects piped in from Get-DbaAgentJob.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Object")]
    public SmoAgentJob[]? InputObject { get; set; }

    /// <summary>Wait for each job to reach an idle state before returning it.</summary>
    [Parameter]
    public SwitchParameter Wait { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which the
    // inherited [Parameter] (no ParameterSetName) already matches; no override needed.

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
            SqlInstance, SqlCredential, Job, ExcludeJob, InputObject, Wait.ToBool(),
            EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess and
    // -FunctionName Stop-DbaAgentJob on the direct Stop-Function/Write-Message sites. Inner $Wait/
    // $EnableException are untyped (a typed [switch] in a positionally-called inner param is skipped by
    // positional binding and shifts later args).
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Job, $ExcludeJob, $InputObject, $Wait, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Job, [string[]]$ExcludeJob, [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject, $Wait, $EnableException, $__realCmdlet)
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Stop-DbaAgentJob
        }

        $InputObject += $server.JobServer.Jobs

        if ($Job) {
            $InputObject = $InputObject | Where-Object Name -In $Job
        }
        if ($ExcludeJob) {
            $InputObject = $InputObject | Where-Object Name -NotIn $ExcludeJob
        }
    }

    foreach ($currentjob in $InputObject) {

        $server = $currentjob.Parent.Parent
        $status = $currentjob.CurrentRunStatus

        if ($status -eq 'Idle') {
            Stop-Function -Message "$currentjob on $server is idle ($status)" -Target $currentjob -Continue -FunctionName Stop-DbaAgentJob
        }

        If ($__realCmdlet.ShouldProcess($server, "Stopping job $currentjob")) {
            $null = $currentjob.Stop()
            Start-Sleep -Milliseconds 300
            $currentjob.Refresh()

            $waits = 0
            while ($currentjob.CurrentRunStatus -ne 'Idle' -and $waits++ -lt 10) {
                Start-Sleep -Milliseconds 100
                $currentjob.Refresh()
            }

            if ($wait) {
                while ($currentjob.CurrentRunStatus -ne 'Idle') {
                    Write-Message -Level Verbose -Message "$currentjob is $($currentjob.CurrentRunStatus)" -FunctionName Stop-DbaAgentJob -ModuleName "dbatools"
                    Start-Sleep -Seconds 3
                    $currentjob.Refresh()
                }
                $currentjob
            } else {
                $currentjob
            }
        }
    }
} $SqlInstance $SqlCredential $Job $ExcludeJob $InputObject $Wait $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
