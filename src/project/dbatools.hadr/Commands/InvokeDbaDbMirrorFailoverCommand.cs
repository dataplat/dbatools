#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Fails over database mirroring configurations to the mirror server.
/// Port of public/Invoke-DbaDbMirrorFailover.ps1; surface pinned by
/// migration/baselines/Invoke-DbaDbMirrorFailover.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbMirrorFailover", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class InvokeDbaDbMirrorFailoverCommand : DbaBaseCmdlet
{
    /// <summary>The primary SQL Server instance.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The mirrored databases to fail over to their mirror partners.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Database objects piped from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Forces an immediate failover allowing data loss, and suppresses prompts.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Invoke-DbaDbMirrorFailover");
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
        // __w4040State sentinel. The loop-less validation Stop-Function+return
        // exits the record via the dot-block frame; the two Test-Bound checks
        // become carried bound flags (they scope-walk the caller).
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4040State"))
            {
                _state = sentinel["__w4040State"] as Hashtable;
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
            SqlInstance, SqlCredential, Database, InputObject,
            Force.ToBool(), EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)), _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's Force -> ConfirmPreference suppression rides verbatim at
    // the hop top, then the source process block VERBATIM, CRLF-preserved and
    // cmp-proven byte-exact after stripping one -FunctionName append (Stop-Function)
    // and reversing the Test-Bound guard substitution (SOURCE comment). ShouldProcess
    // gates use the inner block's own $Pscmdlet (hop-scope-local, so the Force
    // suppression above still applies); the dot-block preserves the return. The
    // W3-082 prompt-state transplant brackets the body: the carried
    // lastShouldProcessContinueStatus is injected before the gates run and harvested
    // after, so Yes/No-to-All spans piped records exactly like the source's single
    // function-scope $Pscmdlet.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $InputObject, $Force, $EnableException, $__boundSqlInstance, $__boundDatabase, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $Force, $EnableException, $__boundSqlInstance, $__boundDatabase, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($Force) { $ConfirmPreference = 'none' }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Invoke-DbaDbMirrorFailover: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if ($__boundSqlInstance -and -not $__boundDatabase) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Invoke-DbaDbMirrorFailover
            return
        }

        $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database

        foreach ($db in $InputObject) {
            # if it's async, you have to break the mirroring and allow data loss
            # alter database set partner force_service_allow_data_loss
            # if it's sync mirroring you know it's all in sync, so you can just do alter database [dbname] set partner failover
            if ($Force) {
                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Forcing failover of $db and allowing data loss")) {
                    $db | Set-DbaDbMirror -State ForceFailoverAndAllowDataLoss
                }
            } else {
                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Setting safety level to full and failing over $db to partner server")) {
                    $db | Set-DbaDbMirror -SafetyLevel Full
                    $db | Set-DbaDbMirror -State Failover
                }
            }
        }
    }

    @{ __w4040State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Database $InputObject $Force $EnableException $__boundSqlInstance $__boundDatabase $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}