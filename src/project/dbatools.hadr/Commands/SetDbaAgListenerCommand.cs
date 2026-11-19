#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the port on an availability group listener.
/// Port of public/Set-DbaAgListener.ps1; surface pinned by
/// migration/baselines/Set-DbaAgListener.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaAgListener", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class SetDbaAgListenerCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group or groups whose listener is being changed.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>The listener or listeners to act on.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Listener { get; set; }

    /// <summary>The new port number.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    public int Port { get; set; }

    /// <summary>Listener objects piped from Get-DbaAgListener.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Set-DbaAgListener");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. No begin block and no Test-FunctionInterrupt, so no DEF-011 latch
        // exposure. NO PARAMETER CARRY: both process-block mutations target the VFP $InputObject,
        // which the binder RE-BINDS every record.
        //
        // BOTH DETECTORS RUN per the DEF-012 sub-class ruling: Get-ParamMutationInventory reports
        // the two $InputObject hits as RE-BOUND, and Get-CrossRecordLeakInventory reports no
        // non-parameter read-before-assign candidates. The second result is treated as a cheap
        // check rather than proof - it catches read-before-assign in SOURCE ORDER and misses the
        // per-BRANCH case, which is exactly how it missed $ag on W4-055 - so the if/else at
        // :104-:110 was read by hand as well. It assigns only $InputObject on both arms; nothing
        // is branch-only-assigned and then read elsewhere.
        //
        // THREE carried bound flags, and one of them is DIFFERENT IN KIND from the family's usual:
        //   :95   Test-Bound -Not SqlInstance, InputObject          -> multi-name, NEITHER bound
        //   :99   (Test-Bound SqlInstance) -and
        //         (Test-Bound -Not AvailabilityGroup)               -> two single-name calls
        //   :105  Test-Bound -ParameterName Listener                -> NOT a guard at all
        //
        // The :105 flag CHOOSES A CODE PATH rather than guarding one: bound selects the
        // Get-DbaAgListener call that passes -Listener (:106), unbound selects the one that omits
        // it (:108). So an explicitly bound but EMPTY -Listener must still take the :106 arm and
        // pass an empty -Listener through - a value test would take :108 instead and silently
        // widen the lookup to every listener in the group. That is the sharpest discriminator on
        // this row and the probe binds -Listener @() specifically to pin it.
        //
        // W3-082 PROMPT-STATE TRANSPLANT: VFP + per-record + inner-$Pscmdlet gate + ConfirmImpact
        // High over a listener port change.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4056State"))
            {
                _state = sentinel["__w4056State"] as Hashtable;
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
            SqlInstance, SqlCredential, AvailabilityGroup, Listener, Port, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            TestBound(nameof(AvailabilityGroup)), TestBound(nameof(Listener)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 95-122 after appending three -FunctionName arguments and reversing FOUR Test-Bound
    // rewrites (SOURCE comments) - three guards plus the path-selecting :105 call. The
    // ShouldProcess gate uses the inner block's own $Pscmdlet; the dot-block preserves the
    // source's two early returns. Bracketing the body: only the W3-082 prompt-state transplant;
    // no parameter carry on this row.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $Listener, $Port, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundAvailabilityGroup, $__boundListener, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, [string[]]$Listener, [int]$Port, [Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundAvailabilityGroup, $__boundListener, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - both process-block param mutations target the VFP $InputObject, which the binder
    # re-binds every record - and no non-parameter cross-record leak (DEF-012 sub-class checked).
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Set-DbaAgListener: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Set-DbaAgListener
            return
        }
        if ($__boundSqlInstance -and (-not $__boundAvailabilityGroup)) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup)) {
            Stop-Function -Message "You must specify one or more Availability Groups when using the SqlInstance parameter." -FunctionName Set-DbaAgListener
            return
        }

        if ($SqlInstance) {
            if ($__boundListener) { # SOURCE: if (Test-Bound -ParameterName Listener) {
                $InputObject += Get-DbaAgListener -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup -Listener $Listener
            } else {
                $InputObject += Get-DbaAgListener -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
            }
        }

        foreach ($aglistener in $InputObject) {
            if ($Pscmdlet.ShouldProcess($aglistener.Parent.Name, "Setting port to $Port for $($aglistener.Name)")) {
                try {
                    $aglistener.PortNumber = $Port
                    $aglistener.Alter()
                    $aglistener
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName Set-DbaAgListener
                }
            }
        }
    }

    @{ __w4056State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $AvailabilityGroup $Listener $Port $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__boundAvailabilityGroup $__boundListener $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
