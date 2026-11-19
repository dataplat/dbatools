#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes database mirroring from a database.
/// Port of public/Remove-DbaDbMirror.ps1; surface pinned by
/// migration/baselines/Remove-DbaDbMirror.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbMirror", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbMirrorCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the mirrored database.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases to remove mirroring from.</summary>
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
        PromptStateTransplant.AssertResolvable("Remove-DbaDbMirror");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. The source has NO begin block and no Test-FunctionInterrupt, so unlike
        // the W4-049 sibling this row has neither a begin/process lifecycle nor DEF-011 latch
        // exposure - checked, not assumed.
        //
        // NO PARAMETER CARRY: the only process-block parameter mutation is
        // `$InputObject += Get-DbaDatabase ...`, and $InputObject is the ValueFromPipeline
        // parameter, which the binder RE-BINDS every record. Nothing is sticky, so the sentinel
        // carries prompt state only.
        //
        // TWO carried bound flags for the compound guard at :89,
        // `(Test-Bound SqlInstance) -and (Test-Bound -Not Database)`. Both are SINGLE-name forms
        // here, unlike the multi-name shapes in W4-045..048, so each maps to one flag. Note this
        // guard keys on BINDING, so an explicitly bound but EMPTY -Database still passes it -
        // the opposite of W4-047's value test in the same structural position. Three rows in this
        // family, three different guard semantics.
        //
        // W3-082 PROMPT-STATE TRANSPLANT: VFP + per-record + inner-$Pscmdlet gate + ConfirmImpact
        // High over a mirroring teardown.
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
            SqlInstance, SqlCredential, Database, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 89-127 after stripping two -FunctionName appends and reversing the two Test-Bound
    // rewrites (SOURCE comment). The source's three explanatory comments - the t-sql rationale at
    // :99 and the two-line Alter()-may-both-succeed-and-error note at :105 - ride untouched. The
    // ShouldProcess gate uses the inner block's own $Pscmdlet; the dot-block preserves the
    // source's early return. Bracketing the body: only the W3-082 prompt-state transplant.
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
        throw "Remove-DbaDbMirror: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if ($__boundSqlInstance -and (-not $__boundDatabase)) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Remove-DbaDbMirror
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Turning off mirror for $db")) {
                # use t-sql cuz $db.Alter() does not always work against restoring dbs
                try {
                    try {
                        $db.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                        $db.Alter()
                    } catch {
                        # The $db.Alter() command may both succeed and return an error code related to the mirror session being stopped.
                        # Refresh the db state and if the mirror session is still active then run the ALTER statement.
                        $db.Refresh()
                        if ($db.IsMirroringEnabled) {
                            try {
                                $db.Parent.Query("ALTER DATABASE $db SET PARTNER OFF")
                            } catch {
                                Stop-Function -Message "Failure on $($db.Parent) for $db" -ErrorRecord $_ -Continue -FunctionName Remove-DbaDbMirror
                            }
                        }
                    }
                    [PSCustomObject]@{
                        ComputerName = $db.ComputerName
                        InstanceName = $db.InstanceName
                        SqlInstance  = $db.SqlInstance
                        Database     = $db.Name
                        Status       = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure on $($db.Parent.Name)" -ErrorRecord $_ -FunctionName Remove-DbaDbMirror
                }
            }
        }
    }

    @{ __w4050State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Database $InputObject $EnableException $__boundSqlInstance $__boundDatabase $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
