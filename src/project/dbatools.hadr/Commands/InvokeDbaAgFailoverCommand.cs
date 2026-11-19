#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Fails over availability groups, gracefully or forcefully with potential data loss.
/// Port of public/Invoke-DbaAgFailover.ps1; surface pinned by
/// migration/baselines/Invoke-DbaAgFailover.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaAgFailover", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class InvokeDbaAgFailoverCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability groups to fail over.</summary>
    [Parameter(Position = 2)]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>Availability group objects piped from Get-DbaAvailabilityGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]? InputObject { get; set; }

    /// <summary>Forces the failover, allowing potential data loss and suppressing prompts.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Invoke-DbaAgFailover");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop per the W3-005/W4-011 convention: the begin block's
        // Force -> ConfirmPreference suppression rides at the hop top and both
        // High-impact ShouldProcess gates run on the INNER scriptblock's own
        // $Pscmdlet - the suppression is hop-scope-local, so -Force still silences
        // the prompt (the ratified Copy-family/W3-005 handling; NOT routed to
        // $__realCmdlet, which reads the outer preference and would re-prompt under
        // -Force). Because InputObject is a per-record VFP axis, the ShouldProcess
        // Yes/No-to-All answer must survive BETWEEN piped records the way the
        // source's single function-scope $Pscmdlet does: the W3-082 prompt-state
        // transplant carries lastShouldProcessContinueStatus through the
        // __w4037State sentinel. The two loop-less validation Stop-Function+return
        // sites exit the record via the dot-block frame; the catch site is
        // -Continue (loop-local).
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4037State"))
            {
                _state = sentinel["__w4037State"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, AvailabilityGroup, InputObject,
            Force.ToBool(), EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's Force -> ConfirmPreference suppression rides verbatim at
    // the hop top, then the source process block VERBATIM, CRLF-preserved and
    // cmp-proven byte-exact after stripping three -FunctionName appends and the one
    // multi-name Test-Bound rewrite (SOURCE comment). ShouldProcess gates use the
    // inner block's own $Pscmdlet (hop-scope-local, so the Force suppression above
    // still applies); the dot-block preserves the validation returns. The W3-082
    // prompt-state transplant brackets the body: the carried
    // lastShouldProcessContinueStatus is injected before the gates run and harvested
    // after, so Yes/No-to-All spans piped records exactly like the source's single
    // function-scope $Pscmdlet.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $InputObject, $Force, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject, $Force, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($Force) { $ConfirmPreference = 'none' }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Invoke-DbaAgFailover: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Invoke-DbaAgFailover
            return
        }

        if ($SqlInstance -and -not $AvailabilityGroup) {
            Stop-Function -Message "You must specify at least one availability group when using SqlInstance." -FunctionName Invoke-DbaAgFailover
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($ag in $InputObject) {
            try {
                $server = $ag.Parent
                if ($Force) {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Forcefully failing over $($ag.Name), allowing potential data loss")) {
                        $ag.FailoverWithPotentialDataLoss()
                        $ag.Refresh()
                        $ag
                    }
                } else {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Gracefully failing over $($ag.Name)")) {
                        $ag.Failover()
                        $ag.Refresh()
                        $ag
                    }
                }
            } catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -FunctionName Invoke-DbaAgFailover
            }
        }
    }

    @{ __w4037State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $AvailabilityGroup $InputObject $Force $EnableException $__boundSqlInstance $__boundInputObject $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
