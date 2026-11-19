#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes endpoints from a SQL Server instance.
/// Port of public/Remove-DbaEndpoint.ps1; surface pinned by
/// migration/baselines/Remove-DbaEndpoint.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaEndpoint", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaEndpointCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the endpoints.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The endpoint or endpoints to remove.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Endpoint { get; set; }

    /// <summary>Remove every endpoint on the instance.</summary>
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
        PromptStateTransplant.AssertResolvable("Remove-DbaEndpoint");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop, and structurally the twin of W4-048 Remove-DbaAvailabilityGroup: one
        // compound guard whose second half is a multi-name Test-Bound -Not naming a [switch].
        //
        // NO PARAMETER CARRY: the only process-block mutation targets the VFP $InputObject, which
        // the binder RE-BINDS every record. No begin block and no Test-FunctionInterrupt, so no
        // DEF-011 latch exposure - checked against the source, not inferred from the sibling.
        //
        // THREE carried bound flags for the single guard at :91,
        //   (Test-Bound SqlInstance) -and (Test-Bound -Not Endpoint, AllEndpoints)
        // rendered as $__boundSqlInstance -and (-not ($__boundEndpoint -or $__boundAllEndpoints)).
        // The -Not form means NEITHER bound, per Test-Bound's own logic (Min=1, Max=length,
        // `return ((-not $Not) -eq $test)`) - the same shape codex verified exhaustively over the
        // eight-row truth table on W4-048.
        //
        // NOTE this row has only ONE guard: unlike W4-045..048 there is NO
        // "supply either -SqlInstance or an InputObject" precondition, so invoking it with
        // nothing bound is legal and simply iterates two empty collections. That asymmetry is
        // easy to miss when working the family in sequence, which is why it is called out here.
        //
        // $AllEndpoints DELIBERATELY DOES NOT RIDE THE HOP, exactly as on W4-048: the source
        // references it ONLY inside that Test-Bound, never as a value, so once the guard becomes
        // a carried bound flag the parameter has no remaining use in the body. Passing it would
        // drag a [switch] into the hop param block - the Class #7/#8 switch-shift trap, where a
        // typed [switch] is excluded from positional binding and silently shifts every parameter
        // after it. Omitting sidesteps the trap rather than working around it.
        //
        // W3-082 PROMPT-STATE TRANSPLANT: VFP + per-record + inner-$Pscmdlet gate + ConfirmImpact
        // High over a DROP ENDPOINT.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4052State"))
            {
                _state = sentinel["__w4052State"] as Hashtable;
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
            SqlInstance, SqlCredential, Endpoint, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Endpoint)), TestBound(nameof(AllEndpoints)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 91-115 after appending two -FunctionName arguments and reversing the single
    // Test-Bound rewrite (SOURCE comment). The source's "# avoid enumeration issues" comment
    // rides untouched. The ShouldProcess gate uses the inner block's own $Pscmdlet; the dot-block
    // preserves the source's early return. Bracketing the body: only the W3-082 prompt-state
    // transplant - no parameter carry on this row.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Endpoint, $InputObject, $EnableException, $__boundSqlInstance, $__boundEndpoint, $__boundAllEndpoints, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Endpoint, [Microsoft.SqlServer.Management.Smo.Endpoint[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundEndpoint, $__boundAllEndpoints, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - the only process-block param mutation targets the VFP $InputObject, which the
    # binder re-binds every record.
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Remove-DbaEndpoint: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if ($__boundSqlInstance -and (-not ($__boundEndpoint -or $__boundAllEndpoints))) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Endpoint, AllEndpoints)) {
            Stop-Function -Message "You must specify AllEndpoints or Endpoint when using the SqlInstance parameter." -FunctionName Remove-DbaEndpoint
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaEndpoint -SqlInstance $instance -SqlCredential $SqlCredential -Endpoint $Endpoint
        }

        foreach ($ep in $InputObject) {
            if ($Pscmdlet.ShouldProcess($ep.Parent.name, "Removing endpoint $ep")) {
                try {
                    # avoid enumeration issues
                    $ep.Parent.Query("DROP ENDPOINT $ep")
                    [PSCustomObject]@{
                        ComputerName = $ep.ComputerName
                        InstanceName = $ep.InstanceName
                        SqlInstance  = $ep.SqlInstance
                        Endpoint     = $ep.Name
                        Status       = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Remove-DbaEndpoint
                }
            }
        }
    }

    @{ __w4052State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Endpoint $InputObject $EnableException $__boundSqlInstance $__boundEndpoint $__boundAllEndpoints $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
