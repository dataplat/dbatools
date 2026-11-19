#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Resumes data movement on an availability group database.
/// Port of public/Resume-DbaAgDbDataMovement.ps1; surface pinned by
/// migration/baselines/Resume-DbaAgDbDataMovement.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Resume, "DbaAgDbDataMovement", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class ResumeDbaAgDbDataMovementCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group to act on. Singular string, not an array.</summary>
    [Parameter(Position = 2)]
    public string? AvailabilityGroup { get; set; }

    /// <summary>The database or databases to resume data movement on.</summary>
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
        PromptStateTransplant.AssertResolvable("Resume-DbaAgDbDataMovement");
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
        // FOUR carried bound flags across THREE guards, and the third guard is written in a shape
        // this family has not used before:
        //   :105  Test-Bound -Not SqlInstance, InputObject          -> multi-name, NEITHER bound
        //   :110  Test-Bound SqlInstance                            -> single-name
        //   :111  (Test-Bound -Not Database) -and (Test-Bound -Not AvailabilityGroup)
        //         -> TWO SEPARATE single-name -Not calls ANDed together, NOT the multi-name form.
        //            It happens to mean the same thing here (neither bound), but it is a distinct
        //            construct and is rewritten as two independent flags rather than assumed
        //            equivalent to the :105 shape.
        //
        // A SOURCE BUG THAT RIDES BUG-FOR-BUG - the ShouldProcess call at :122 reads
        //     $Pscmdlet.ShouldProcess($ag.Parent.Name, "Seting availability group $db to $($db.Parent.Name)")
        // but the loop variable is $agdb. Neither $ag nor $db exists, so the TARGET is empty and
        // the message interpolates two empty strings (the "Seting" typo is the source's too). Both
        // resolve empty in the hop exactly as they do in the function - verified by querying the
        // dbatools module script scope directly, which defines neither name.
        //
        // CORRECTION (codex r1, and it is right): an earlier version of this comment claimed that
        // IF the module defined $ag or $db, the hop would silently pick it up and DIVERGE from the
        // function. That reasoning was wrong. The source function is ITSELF module-bound - it lives
        // in the dbatools module and resolves undefined locals against the SAME module script scope
        // the hop does. A module-scope $ag would therefore be seen by BOTH worlds, and there is no
        // divergence for it to create. The check was still worth running, but the hazard it was
        // guarding against does not exist for a module-scoped source function.
        //
        // W3-082 PROMPT-STATE TRANSPLANT: VFP + per-record + inner-$Pscmdlet gate + ConfirmImpact
        // High.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4054State"))
            {
                _state = sentinel["__w4054State"] as Hashtable;
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
    // lines 105-130 after appending two -FunctionName arguments and reversing FOUR Test-Bound
    // rewrites (SOURCE comments). The ShouldProcess gate uses the inner block's own $Pscmdlet and
    // keeps the source's undefined $ag/$db references and "Seting" typo exactly as written.
    // Bracketing the body: only the W3-082 prompt-state transplant; no parameter carry.
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
        throw "Resume-DbaAgDbDataMovement: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Resume-DbaAgDbDataMovement
            return
        }

        if ($__boundSqlInstance) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance)) {
            if ((-not $__boundDatabase) -and (-not $__boundAvailabilityGroup)) { # SOURCE: if ((Test-Bound -Not -ParameterName Database) -and (Test-Bound -Not -ParameterName AvailabilityGroup)) {
                Stop-Function -Message "You must specify one or more databases and one Availability Groups when using the SqlInstance parameter." -FunctionName Resume-DbaAgDbDataMovement
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaAgDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($agdb in $InputObject) {
            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Seting availability group $db to $($db.Parent.Name)")) {
                try {
                    $null = $agdb.ResumeDataMovement()
                    $agdb
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Resume-DbaAgDbDataMovement
                }
            }
        }
    }

    @{ __w4054State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $AvailabilityGroup $Database $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__boundDatabase $__boundAvailabilityGroup $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
