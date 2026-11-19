#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Stops one or more SQL Server endpoints.
/// Port of public/Stop-DbaEndpoint.ps1; surface pinned by
/// migration/baselines/Stop-DbaEndpoint.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Stop, "DbaEndpoint", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class StopDbaEndpointCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the endpoint.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The endpoint or endpoints to stop.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Endpoint { get; set; }

    /// <summary>Stop all endpoints on the instance.</summary>
    [Parameter]
    public SwitchParameter AllEndpoints { get; set; }

    /// <summary>Endpoint objects piped from Get-DbaEndpoint.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.Endpoint[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Stop-DbaEndpoint");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. No begin block and no Test-FunctionInterrupt in the source, so no
        // begin/process lifecycle and no DEF-011 latch exposure - checked against this source.
        //
        // The MIRROR TWIN of Start-DbaEndpoint (W4-061). Compare-Object over the two process
        // bodies shows the guard, accumulate, VFP and single gate line-for-line identical; the
        // only differences are ConfirmImpact HIGH (not Low), the gate message "Stopping" and
        // $ep.Stop(). The HIGH impact makes the W3-082 transplant meaningfully load-bearing here -
        // a "yes to all" answered at record 1 must survive to record 2 - where the sibling's Low
        // impact left it precautionary.
        //
        // NO PARAMETER CARRY. The only process-block parameter mutation is `$InputObject +=` at
        // :100, targeting the ValueFromPipeline parameter, which the binder RE-BINDS every record.
        // Both detectors clean; I also read the branches by hand ($instance and $ep are foreach
        // variables assigned before every read on every path).
        //
        // THREE carried bound flags for the guard at :95: single-name SqlInstance plus the
        // MULTI-NAME -Not over Endpoint and AllEndpoints (NEITHER bound), which becomes
        // -not ($__boundEndpoint -or $__boundAllEndpoints). Keys on BINDING: -Endpoint bound
        // EMPTY still clears it.
        //
        // W3-082 PROMPT-STATE TRANSPLANT: VFP + per-record + an inner $Pscmdlet gate at :105
        // under ConfirmImpact High.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4050State"))
            {
                _state = sentinel["__w4050State"] as Hashtable;
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
            SqlInstance, SqlCredential, Endpoint,
            AllEndpoints.ToBool(), InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Endpoint)), TestBound(nameof(AllEndpoints)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 95-112 after stripping one -FunctionName append and reversing the single Test-Bound
    // rewrite (the compound guard at :95). $AllEndpoints is passed UNTYPED and as .ToBool() - a
    // typed [switch] in a hop param block is excluded from positional binding (class #7/#8
    // switch-shift). The gate uses the inner block's own $Pscmdlet; the dot-block preserves the
    // source's early return at :97. Bracketing the body: only the W3-082 prompt-state transplant.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Endpoint, $AllEndpoints, $InputObject, $EnableException, $__boundSqlInstance, $__boundEndpoint, $__boundAllEndpoints, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Endpoint, $AllEndpoints, [Microsoft.SqlServer.Management.Smo.Endpoint[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundEndpoint, $__boundAllEndpoints, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - the only process-block param mutation targets the VFP $InputObject, which the
    # binder re-binds every record.
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Stop-DbaEndpoint: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if ($__boundSqlInstance -And (-not ($__boundEndpoint -or $__boundAllEndpoints))) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -And (Test-Bound -Not -ParameterName Endpoint, AllEndpoints)) {
            Stop-Function -Message "You must specify AllEndpoints or Endpoint when using the SqlInstance parameter." -FunctionName Stop-DbaEndpoint
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaEndpoint -SqlInstance $instance -SqlCredential $SqlCredential -Endpoint $Endpoint
        }

        foreach ($ep in $InputObject) {
            try {
                if ($Pscmdlet.ShouldProcess($ep.Parent.Name, "Stopping $ep")) {
                    $ep.Stop()
                    $ep
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Stop-DbaEndpoint
            }
        }
    }

    @{ __w4050State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Endpoint $AllEndpoints $InputObject $EnableException $__boundSqlInstance $__boundEndpoint $__boundAllEndpoints $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
