#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets mirroring properties - partner, witness, safety level and state - on a database.
/// Port of public/Set-DbaDbMirror.ps1; surface pinned by
/// migration/baselines/Set-DbaDbMirror.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbMirror", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class SetDbaDbMirrorCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the database.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases to modify.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The mirroring partner endpoint URL.</summary>
    [Parameter(Position = 3)]
    public string? Partner { get; set; }

    /// <summary>The mirroring witness endpoint URL.</summary>
    [Parameter(Position = 4)]
    public string? Witness { get; set; }

    /// <summary>The transaction safety level.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("Full", "Off", "None")]
    [PsStringCast]
    public string? SafetyLevel { get; set; }

    /// <summary>The mirroring state to move the database to.</summary>
    [Parameter(Position = 6)]
    [ValidateSet("ForceFailoverAndAllowDataLoss", "Failover", "RemoveWitness", "Resume", "Suspend", "Off")]
    [PsStringCast]
    public string? State { get; set; }

    /// <summary>Database objects piped from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 7)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Set-DbaDbMirror");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. No begin block and no Test-FunctionInterrupt in the source, so no
        // begin/process lifecycle and no DEF-011 latch exposure - checked against the source, not
        // inherited from the W4-050 sibling this row otherwise mirrors.
        //
        // NO PARAMETER CARRY, both detectors clean. The only process-block parameter mutation is
        // `$InputObject += Get-DbaDatabase ...` at :125, and $InputObject is the ValueFromPipeline
        // parameter, which the binder RE-BINDS every record - nothing sticky. The cross-record
        // leak detector reports no non-parameter read-before-assign; I also read the branches by
        // hand rather than trusting that report alone, because the tool catches SOURCE order and
        // not per-BRANCH order (the gap that cost W4-055 its $ag). $db and $instance are both
        // foreach-assigned before every read, on every path.
        //
        // TWO carried bound flags for the compound guard at :120,
        // `(Test-Bound SqlInstance) -and (Test-Bound -Not Database)`. Both SINGLE-name, so one
        // flag each. This is byte-identical to W4-050's guard, and like it keys on BINDING - an
        // explicitly bound but EMPTY -Database still passes. The four scalars below it
        // (Partner/Witness/SafetyLevel/State) are VALUE tests - plain `if ($Partner)` - so they
        // ride the hop untouched and need no flag; the row therefore mixes both guard semantics
        // in one body, which is why each was classified separately rather than as a family.
        //
        // W3-082 PROMPT-STATE TRANSPLANT, and this row leans on it harder than any sibling so far:
        // FOUR separate $Pscmdlet.ShouldProcess gates under ConfirmImpact High, of which at most
        // THREE are reachable per database - the witness gate is an elseif and is unreachable
        // whenever -Partner is truthy (codex correction to my first phrasing, which said all four
        // were reachable together; the parity probe's all-four scenario indeed observes three).
        // Without the transplant a "yes to all" answered at the partner gate would be forgotten by
        // the safety-level gate two lines later - re-prompting mid-record, not merely across
        // records, which is what makes the transplant load-bearing here rather than precautionary.
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
            SqlInstance, SqlCredential, Database, Partner, Witness, SafetyLevel, State, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(Database)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 119-159 after stripping two -FunctionName appends and reversing the single Test-Bound
    // rewrite (SOURCE comment). The source's two comments ride untouched: the t-sql rationale at
    // :132 and the COMMENTED-OUT `# $db.MirroringSafetyLevel = $SafetyLevel` at :144 - that second
    // one is dead code in the source and stays dead code here, preserved rather than tidied away
    // per the comment mandate. The four ShouldProcess gates use the inner block's own $Pscmdlet;
    // the dot-block preserves the source's early return at :122. Bracketing the body: only the
    // W3-082 prompt-state transplant.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Partner, $Witness, $SafetyLevel, $State, $InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string]$Partner, [string]$Witness, [string]$SafetyLevel, [string]$State, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundDatabase, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - the only process-block param mutation targets the VFP $InputObject, which the
    # binder re-binds every record. The FOUR gates below make this restore matter within a
    # single record too, not only across records.
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Set-DbaDbMirror: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if ($__boundSqlInstance -and (-not $__boundDatabase)) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified" -FunctionName Set-DbaDbMirror
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            try {
                if ($Partner) {
                    if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Setting partner on $db")) {
                        # use t-sql cuz $db.Alter() does not always work against restoring dbs
                        $db.Parent.Query("ALTER DATABASE $db SET PARTNER = N'$Partner'")
                    }
                } elseif ($Witness) {
                    if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Setting witness on $db")) {
                        $db.Parent.Query("ALTER DATABASE $db SET WITNESS = N'$Witness'")
                    }
                }

                if ($SafetyLevel) {
                    if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Changing safety level to $SafetyLevel on $db")) {
                        $db.Parent.Query("ALTER DATABASE $db SET PARTNER SAFETY $SafetyLevel")
                        # $db.MirroringSafetyLevel = $SafetyLevel
                    }
                }

                if ($State) {
                    if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Changing mirror state to $State on $db")) {
                        $db.ChangeMirroringState($State)
                        $db.Alter()
                        $db
                    }
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName Set-DbaDbMirror
            }
        }
    }

    @{ __w4050State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Database $Partner $Witness $SafetyLevel $State $InputObject $EnableException $__boundSqlInstance $__boundDatabase $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
