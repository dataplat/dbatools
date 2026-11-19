#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes specified job steps from SQL Server Agent jobs.
/// </summary>
/// <remarks>
/// The instance connection, the job/step validation, the confirmation gate, and the Drop all run the
/// original dbatools PowerShell body inside the dbatools module scope rather than being reimplemented
/// in C#, so the engine decides the observable details. The process hop is whole-array: the
/// confirmation gate sits inside the instance/job loops, routed to this cmdlet's real ShouldProcess
/// runtime (ConfirmImpact High), and the two loops must share one invocation so a labeled continue
/// unwinds both of them exactly as it does in the script (see below). The hop is buffered - the body
/// emits no success output (the function returns nothing), so there is no output to lose to a later
/// terminating failure.
///
/// Known behavioral note, preserved deliberately: both validation failures call
/// Stop-Function -Continue -ContinueLabel main, but NO enclosing loop carries a :main label - the
/// label is dangling in the original source and is kept verbatim here. In the script world an
/// unmatched labeled continue unwinds past every enclosing loop and the function itself, silently
/// terminating the whole invocation: with several instances PIPED in, a missing job or step on one
/// record also kills every later record and skips the end block. The unwind does not stop at the
/// call site either - it escapes the CALLER's own loops as well, so the statement after the call
/// never runs and the script exits 0 with no error record. In this compiled cmdlet each
/// pipeline record runs its own hop invocation, which CONTAINS the unwind: within one record
/// (array-valued -SqlInstance or -Job) the remaining items are skipped exactly like the source, but
/// later piped records still process and the end block's closing verbose message still appears. That
/// containment matches the evident intent of the source ("skip to the next item"); the
/// whole-invocation abort is a source bug not replicated here, because the escape leaves no
/// detectable signal in the wrapper (it returns normally, no error record, no exception) and adding
/// the missing label would change the script world's behavior. The difference exists only on the
/// default warning path: under -EnableException, Stop-Function throws a terminating error before any
/// labeled continue is reached, and both worlds abort the invocation identically.
///
/// $JobStep is function-scope state in the source: if its assignment throws on a later pipeline
/// record, the source's catch reports Stop-Function -Target with the PREVIOUS record's step still in
/// the variable, which a fresh per-record hop scope would replace with null. The hop therefore seeds
/// $JobStep from a value carried on this cmdlet instance and emits it back through a sentinel after
/// each record. When the dangling labeled continue escapes a record, that record's sentinel is
/// skipped and the carrier keeps the last completed record's value - later records only exist at all
/// under the containment divergence above, which already has no source-side behavior to match.
///
/// Surface pinned by migration/baselines/Remove-DbaAgentJobStep.json.
/// </remarks>
[Cmdlet(VerbsCommon.Remove, "DbaAgentJobStep", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaAgentJobStepCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The SQL Agent job(s) from which to remove the step.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [ValidateNotNullOrEmpty]
    public object[] Job { get; set; } = null!;

    /// <summary>The exact name of the job step to remove from the specified jobs.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [ValidateNotNullOrEmpty]
    [PsStringCast]
    public string StepName { get; set; } = null!;

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare, which the
    // inherited [Parameter] already matches; no override needed.

    // The source's function-scope $JobStep, carried across pipeline records (see the class remarks).
    private object? _jobStep;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__removeDbaAgentJobStepState"))
            {
                if (sentinel["__removeDbaAgentJobStepState"] is Hashtable state)
                {
                    _jobStep = state["JobStep"];
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Job, StepName, EnableException.ToBool(), _jobStep, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            if (item is not null)
            {
                WriteObject(item);
            }
        }
    }

    // PS: the process block VERBATIM apart from $PSCmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess
    // and -FunctionName Remove-DbaAgentJobStep (+ -ModuleName "dbatools" on Write-Message, whose
    // metadata otherwise resolves from the generated scriptblock frame) on the direct
    // Stop-Function/Write-Message sites. The dangling -ContinueLabel main is preserved as-is (see the
    // class remarks). EnableException is bound so Stop-Function's scope-walking default inherits it.
    // $JobStep seeds from the carried instance state and the trailing sentinel hands it back (the
    // sentinel is skipped when the labeled continue escapes the record - remarks cover why that is
    // acceptable); the C# swallows the sentinel, so it never reaches the caller.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Job, $StepName, $EnableException, $__carriedJobStep, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Job, [string]$StepName, $EnableException, $__carriedJobStep, $__realCmdlet)
    # Seed the carried cross-record state of $JobStep (source keeps it in the shared process scope).
    $JobStep = $__carriedJobStep
    foreach ($instance in $SqlInstance) {

        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaAgentJobStep
        }

        foreach ($j in $Job) {
            Write-Message -Level Verbose -Message "Processing job $j" -FunctionName Remove-DbaAgentJobStep -ModuleName "dbatools"
            # Check if the job exists
            if ($Server.JobServer.Jobs.Name -notcontains $j) {
                Stop-Function -Message "Job $j doesnn't exist on $instance." -Continue -ContinueLabel main -Target $instance -Category InvalidData -FunctionName Remove-DbaAgentJobStep
            } else {
                # Check if the job step exists
                if ($Server.JobServer.Jobs[$j].JobSteps.Name -notcontains $StepName) {
                    Stop-Function -Message "Step $StepName doesn't exist for $job on $instance." -Continue -ContinueLabel main -Target $instance -Category InvalidData -FunctionName Remove-DbaAgentJobStep
                } else {
                    # Execute
                    if ($__realCmdlet.ShouldProcess($instance, "Removing the job step $StepName for job $j")) {
                        try {
                            $JobStep = $Server.JobServer.Jobs[$j].JobSteps[$StepName]
                            Write-Message -Level SomewhatVerbose -Message "Removing the job step $StepName for job $j." -FunctionName Remove-DbaAgentJobStep -ModuleName "dbatools"
                            $JobStep.Drop()
                        } catch {
                            Stop-Function -Message "Something went wrong removing the job step" -Target $JobStep -Continue -ErrorRecord $_ -FunctionName Remove-DbaAgentJobStep
                            Write-Message -Level Verbose -Message "Could not remove the job step $StepName from $j" -FunctionName Remove-DbaAgentJobStep -ModuleName "dbatools"
                        }
                    }
                }
            }
        }
    }

    @{ __removeDbaAgentJobStepState = @{ JobStep = $JobStep } }
} $SqlInstance $SqlCredential $Job $StepName $EnableException $__carriedJobStep $__realCmdlet @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM apart from -FunctionName/-ModuleName on the Write-Message.
    // EnableException is bound so the hop scope mirrors the source function scope.
    private const string EndScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException)
    Write-Message -Message "Finished removing the jobs step(s)" -Level Verbose -FunctionName Remove-DbaAgentJobStep -ModuleName "dbatools"
} $EnableException @__commonParameters 3>&1 2>&1
""";
}
