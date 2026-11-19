#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Attempts to repair a suspended database mirror by cycling the mirroring endpoints and
/// resuming the mirror.
/// Port of public/Repair-DbaDbMirror.ps1; surface pinned by
/// migration/baselines/Repair-DbaDbMirror.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Repair, "DbaDbMirror", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RepairDbaDbMirrorCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the mirrored database.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases to repair.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Database objects piped from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Repair-DbaDbMirror");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. No begin block, no Test-FunctionInterrupt, so no DEF-011 latch
        // exposure. NO PARAMETER CARRY: the only process-block mutation targets the VFP
        // $InputObject, which the binder RE-BINDS every record.
        //
        // TWO carried bound flags for the guard at :97,
        // (Test-Bound SqlInstance) -and (Test-Bound -Not Database) - both SINGLE-name forms
        // keying on BINDING, identical in shape to W4-050.
        //
        // A SOURCE QUIRK THAT MUST RIDE BUG-FOR-BUG, and it is the opposite of what the cmdlet
        // name and ConfirmImpact High imply: the $Pscmdlet.ShouldProcess gate at :110 wraps ONLY
        // `$db` - i.e. "displaying output". The actual repair actions - Stop-DbaEndpoint,
        // Start-DbaEndpoint and Set-DbaDbMirror -State Resume at :107-:109 - all sit OUTSIDE it.
        // So in the source, -WhatIf does NOT prevent the repair; it only suppresses the emitted
        // database object. That is almost certainly not what the author intended, but it is what
        // the command does, and a port that "fixed" it by widening the gate would change
        // behaviour under -WhatIf for every existing caller. The gate placement is reproduced
        // exactly as written; the probe pins it so the quirk cannot be silently lost later.
        //
        // W3-082 PROMPT-STATE TRANSPLANT: VFP + per-record + inner-$Pscmdlet gate. Note the
        // consequence of the quirk above - the prompt here governs OUTPUT, not the mutation, so
        // answering No still leaves the endpoints cycled and the mirror resumed.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4053State"))
            {
                _state = sentinel["__w4053State"] as Hashtable;
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
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 97-116 after appending two -FunctionName arguments and reversing the two Test-Bound
    // rewrites (SOURCE comment). The ShouldProcess gate uses the inner block's own $Pscmdlet and
    // sits exactly where the source puts it - around the output only. Bracketing the body: only
    // the W3-082 prompt-state transplant; no parameter carry on this row.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - the only process-block param mutation targets the VFP $InputObject, which the
    # binder re-binds every record.
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Repair-DbaDbMirror: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if ($__boundSqlInstance -and (-not $__boundDatabase)) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Repair-DbaDbMirror
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            try {
                Get-DbaEndpoint -SqlInstance $db.Parent | Where-Object EndpointType -eq DatabaseMirroring | Stop-DbaEndpoint
                Get-DbaEndpoint -SqlInstance $db.Parent | Where-Object EndpointType -eq DatabaseMirroring | Start-DbaEndpoint
                $db | Set-DbaDbMirror -State Resume
                if ($Pscmdlet.ShouldProcess("console", "displaying output")) {
                    $db
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName Repair-DbaDbMirror
            }
        }
    }

    @{ __w4053State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Database $InputObject $EnableException $__boundSqlInstance $__boundDatabase $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
