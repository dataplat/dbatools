#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Suspends data movement for one or more availability group databases.
/// Port of public/Suspend-DbaAgDbDataMovement.ps1; surface pinned by
/// migration/baselines/Suspend-DbaAgDbDataMovement.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Suspend, "DbaAgDbDataMovement", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class SuspendDbaAgDbDataMovementCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group whose database data movement to suspend.</summary>
    [Parameter(Position = 2)]
    public string? AvailabilityGroup { get; set; }

    /// <summary>The database or databases to suspend data movement for.</summary>
    // T8/DEF-002 FIXED by [PsStringArrayCast] (PsCompat now present in hadr, ab7492c). The source's
    // [string[]]$Database casts AT BIND TIME, so `-Database @($null)` coerces the null element to ""
    // before Get-DbaAgDatabase sees it; the compiled binder keeps the raw null and the hop's inner
    // [string[]] param does NOT re-cast a null ELEMENT, so without this the two worlds passed <''>
    // vs <null> to the lookup (measured directly against the real cmdlet). The cast happens before
    // validators, matching the function world. This is the ONLY value-flowing string parameter:
    // $AvailabilityGroup's value is never used (only its Test-Bound binding is), so it needs no cast.
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Availability database objects piped from Get-DbaAgDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityDatabase[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Suspend-DbaAgDbDataMovement");
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
        // NO PARAMETER CARRY. The only process-block parameter mutation is `$InputObject +=` at
        // :115, targeting the ValueFromPipeline parameter, which the binder RE-BINDS every record.
        // Both detectors clean; I also read the branches by hand.
        //
        // FOUR carried bound flags for THREE guards:
        //   :102  the POSITIONAL multi-name -Not over SqlInstance, InputObject (NEITHER bound)
        //         -> -not ($__boundSqlInstance -or $__boundInputObject);
        //   :107  single-name SqlInstance;
        //   :108  two single-name -Not (Database, AvailabilityGroup).
        // InputObject is itself one of the guarded names, and it is the VFP parameter, so its flag
        // MUST be the C#-computed MyInvocation.BoundParameters value - the hop binds it by
        // construction, so a Test-Bound inside the hop would wrongly always report it bound. This
        // is exactly why the flags are computed out here rather than inside.
        //
        // SOURCE BUG PRESERVED BUG-FOR-BUG (NOT a leak, NOT carried): the gate at :119 reads $ag
        // and $db, and NEITHER is ever assigned anywhere in the function - the loop variable is
        // $agdb. Both resolve IDENTICALLY in BOTH worlds: the source function scope-walks the
        // undefined name outward, and the hop scope-walks the same undefined name through the SAME
        // module session-state chain. With no $script:ag/$global:ag defined (the normal case) that
        // is $null, so the ShouldProcess target/message come through empty; if such a variable
        // DID exist both worlds would resolve it to the same value (codex correction - the claim
        // is IDENTICAL-resolution, not unconditionally-null; the parity probe clears $script/
        // $global $ag/$db so its emptiness assertion is not accidentally satisfied by ambient
        // state). This is the W4-054 situation (a variable undefined-in-function resolves
        // identically), NOT the W4-055 leak (assigned in one branch, read in another). Carrying
        // them would be wrong: there is nothing to carry.
        //
        // [T8/DEF-002] the -Database @($null) bind-time cast: FIXED by [PsStringArrayCast] on the
        // Database property (PsCompat now present in hadr via ab7492c), casting the null element to
        // "" at bind time to match the function world (measured: compiled now passes <''> not
        // <null> to the lookup). See the Database property comment.
        //
        // [DEF-001] CLOSED via InvokeScopedStreaming (ab7492c). It fixes the emit-and-throw AND keeps
        // the real behaviour identical (WhatIf still prevents the mutation, message still prints to
        // console). It DOES change ShouldProcess -WhatIf TRANSCRIPT capture (Start-Transcript in a
        // child process captures the function/buffered WhatIf message but not the streaming one - a
        // narrow logging observability change, documented, repro at tools/diag-w4063-streaming-whatif
        // -transcript.ps1). Confirmed a non-blocker: the fleet streamed ShouldProcess rows through it
        // (C's 62-port wave) and MSTest passed 487/487, which tests behaviour not WhatIf-transcript.
        // The parity runner now compares gate BEHAVIOUR (mutation prevented) not the transcript
        // gate-message. The state sentinel rides the streaming callback as the last emitted item.
        //
        // W3-082 PROMPT-STATE TRANSPLANT: VFP + per-record + an inner $Pscmdlet gate at :119
        // under ConfirmImpact High.
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
            SqlInstance, SqlCredential, AvailabilityGroup, Database, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            TestBound(nameof(Database)), TestBound(nameof(AvailabilityGroup)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 102-127 after stripping three -FunctionName appends and reversing the FOUR Test-Bound
    // rewrites (the positional multi-name -Not at :102, the single-name at :107, and the two
    // single-name -Not at :108). The source's "Seting" typo at :119 and its undefined $ag/$db in
    // the gate expression ride untouched. $EnableException is passed untyped/.ToBool(). The gate
    // uses the inner block's own $Pscmdlet; the dot-block preserves the source's early returns at
    // :104 and :110. Bracketing the body: only the W3-082 prompt-state transplant.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $Database, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundDatabase, $__boundAvailabilityGroup, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$AvailabilityGroup, [string[]]$Database, [Microsoft.SqlServer.Management.Smo.AvailabilityDatabase[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundDatabase, $__boundAvailabilityGroup, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified). No parameter carry on this
    # row - the only process-block param mutation targets the VFP $InputObject, which the
    # binder re-binds every record.
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Suspend-DbaAgDbDataMovement: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Suspend-DbaAgDbDataMovement
            return
        }

        if (($__boundSqlInstance)) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance)) {
            if ((-not $__boundDatabase) -and (-not $__boundAvailabilityGroup)) { # SOURCE: if ((Test-Bound -Not -ParameterName Database) -and (Test-Bound -Not -ParameterName AvailabilityGroup)) {
                Stop-Function -Message "You must specify one or more databases and one Availability Groups when using the SqlInstance parameter." -FunctionName Suspend-DbaAgDbDataMovement
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaAgDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($agdb in $InputObject) {
            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Seting availability group $db to $($db.Parent.Name)")) {
                try {
                    $null = $agdb.SuspendDataMovement()
                    $agdb
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Suspend-DbaAgDbDataMovement
                }
            }
        }
    }

    @{ __w4050State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $AvailabilityGroup $Database $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__boundDatabase $__boundAvailabilityGroup $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
