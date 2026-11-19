#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes a listener from an availability group.
/// Port of public/Remove-DbaAgListener.ps1; surface pinned by
/// migration/baselines/Remove-DbaAgListener.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaAgListener", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaAgListenerCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The listener or listeners to remove.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Listener { get; set; }

    /// <summary>The availability group or groups to remove the listeners from.</summary>
    [Parameter(Position = 3)]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>Listener objects piped from Get-DbaAgListener.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Remove-DbaAgListener");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop, and the near-twin of W4-045 Remove-DbaAgDatabase - same validation
        // ladder, same multi-name Test-Bound, same High-impact inner gate around a drop.
        //
        // IT DIFFERS IN ONE IMPORTANT WAY: there is NO cross-record parameter carry here. The
        // sibling accumulates `$Database += $InputObject.Name`, which is sticky and must ride
        // the sentinel; this row has no such accumulation. Its ONLY process-block parameter
        // mutation is `$InputObject += Get-DbaAgListener ...`, and $InputObject is the
        // ValueFromPipeline parameter, which the binder RE-BINDS every record - so carrying it
        // would be wrong, not merely unnecessary (Rule 1,
        // notes/W4-043-vfp-rebind-probe.txt). The sentinel therefore carries prompt state only.
        //
        // W3-082 PROMPT-STATE TRANSPLANT still applies - Class-2 signature: VFP InputObject +
        // per-record ProcessRecord + inner-$Pscmdlet gate + ConfirmImpact High, gating a
        // data-loss drop, so Yes/No-to-All must persist across piped records.
        //
        // Test-Bound scope-walks the caller and cannot ride a hop, so its three sites become
        // carried bound flags; :87 is the MULTI-NAME -Not form, meaning NEITHER bound. The
        // loop-less validation returns exit the record via the dot-block frame; the in-loop
        // failure site is -Continue.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4046State"))
            {
                _state = sentinel["__w4046State"] as Hashtable;
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
            SqlInstance, SqlCredential, Listener, AvailabilityGroup, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(Listener)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 87-120 after stripping three -FunctionName appends and reversing three Test-Bound
    // rewrites (SOURCE comments). The ShouldProcess gate uses the inner block's own $Pscmdlet;
    // the dot-block preserves the source's two early returns. Bracketing the body: only the
    // W3-082 prompt-state transplant, injected before any gate and harvested by the tail -
    // there is no parameter carry on this row.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Listener, $AvailabilityGroup, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundListener, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Listener, [string[]]$AvailabilityGroup, [Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundListener, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - the only process-block param mutation targets the VFP $InputObject, which the
    # binder re-binds every record.
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Remove-DbaAgListener: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Remove-DbaAgListener
            return
        }

        if ($__boundSqlInstance) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance)) {
            if (-not $__boundListener) { # SOURCE: if ((Test-Bound -Not -ParameterName Listener)) {
                Stop-Function -Message "You must specify one or more listeners and one or more Availability Groups when using the SqlInstance parameter." -FunctionName Remove-DbaAgListener
                return
            }
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAgListener -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Listener $Listener
        }

        foreach ($aglistener in $InputObject) {
            if ($Pscmdlet.ShouldProcess($aglistener.Parent.Parent.Name, "Removing availability group listener $aglistener")) {
                try {
                    $ag = $aglistener.Parent.Name
                    $aglistener.Parent.AvailabilityGroupListeners[$aglistener.Name].Drop()
                    [PSCustomObject]@{
                        ComputerName      = $aglistener.ComputerName
                        InstanceName      = $aglistener.InstanceName
                        SqlInstance       = $aglistener.SqlInstance
                        AvailabilityGroup = $ag
                        Listener          = $aglistener.Name
                        Status            = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Remove-DbaAgListener
                }
            }
        }
    }

    @{ __w4046State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Listener $AvailabilityGroup $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__boundListener $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
