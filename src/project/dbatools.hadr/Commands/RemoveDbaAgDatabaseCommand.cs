#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes a database from an availability group.
/// Port of public/Remove-DbaAgDatabase.ps1; surface pinned by
/// migration/baselines/Remove-DbaAgDatabase.json.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaAgDatabase", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaAgDatabaseCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases to remove from the availability group.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>The availability group or groups to remove the databases from.</summary>
    [Parameter(Position = 3)]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>Database or availability-group-database objects piped in - deliberately generic.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Remove-DbaAgDatabase");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. The source has NO begin block. Two class signatures land on this
        // row at once:
        //
        // (1) CROSS-RECORD PARAMETER CARRY, the direction that actually breaks. The source
        //     does `$Database += $InputObject.Name` UNGUARDED, and PowerShell parameters are
        //     function-scope, so record 2 starts from record 1's accumulated list and widens
        //     the Get-DbaAgDatabase lookup below it. A per-record hop hands each record FRESH
        //     parameters, so that accumulation would silently vanish - $Database rides the
        //     __w4045State sentinel and the quirk is reproduced bug-for-bug, not fixed.
        //     $InputObject is also mutated (`+= Get-DbaAgDatabase ...`) but it is the
        //     ValueFromPipeline parameter and the binder RE-BINDS it every record, so it must
        //     NOT be carried (Rule 1, notes/W4-043-vfp-rebind-probe.txt).
        //
        // (2) W3-082 PROMPT-STATE TRANSPLANT, Class-2 signature: VFP InputObject + per-record
        //     ProcessRecord + inner-$Pscmdlet gate + ConfirmImpact High. The gated action is a
        //     DATA-LOSS drop of an availability-group database, so losing the Yes/No-to-All
        //     answer between piped records is precisely the safety divergence the class fix
        //     exists to prevent.
        //
        // Test-Bound scope-walks the caller and cannot ride a hop, so its three sites become
        // carried bound flags. The :94 site uses the MULTI-NAME -Not form, which per
        // Test-Bound's own logic (Min=1, Max=length, `return ((-not $Not) -eq $test)`) means
        // NEITHER bound. The loop-less validation returns exit the record via the dot-block
        // frame; the in-loop failure site is -Continue.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4045State"))
            {
                _state = sentinel["__w4045State"] as Hashtable;
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
            SqlInstance, SqlCredential, Database, AvailabilityGroup, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)), TestBound(nameof(Database)),
            _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 94-133 after stripping three -FunctionName appends and reversing three Test-Bound
    // rewrites (SOURCE comments). The ShouldProcess gate uses the inner block's own $Pscmdlet;
    // the dot-block preserves the source's two early returns. Bracketing the body: the carried
    // $Database accumulation is seeded BEFORE the body so it observes the source's cross-record
    // state, and the W3-082 prompt-state transplant is injected before any gate; the tail
    // harvests both into the sentinel.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $AvailabilityGroup, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundDatabase, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$AvailabilityGroup, [object[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundDatabase, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record PARAMETER state: the source accumulates into $Database in process{} and
    # parameters are fn-scope, so a later piped record observes the earlier record's widened
    # list. Seeded on ContainsKey so a carried $null is restored too - the source's parameter
    # simply holds whatever the previous record left, including nothing.
    if ($null -ne $__state -and $__state.ContainsKey('database')) {
        $Database = $__state.database
    }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Remove-DbaAgDatabase: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Remove-DbaAgDatabase
            return
        }

        if ($__boundSqlInstance) { # SOURCE: if ((Test-Bound -ParameterName SqlInstance)) {
            if (-not $__boundDatabase) { # SOURCE: if ((Test-Bound -Not -ParameterName Database)) {
                Stop-Function -Message "You must specify one or more databases and one or more Availability Groups when using the SqlInstance parameter." -FunctionName Remove-DbaAgDatabase
                return
            }
        }

        if ($InputObject) {
            if ($InputObject[0].GetType().Name -eq 'Database') {
                $Database += $InputObject.Name
            }
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAgDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ($Pscmdlet.ShouldProcess($db.Parent.Parent.Name, "Removing availability group database $db")) {
                try {
                    $ag = $db.Parent.Name
                    $db.Parent.AvailabilityDatabases[$db.Name].Drop()
                    [PSCustomObject]@{
                        ComputerName      = $db.ComputerName
                        InstanceName      = $db.InstanceName
                        SqlInstance       = $db.SqlInstance
                        AvailabilityGroup = $ag
                        Database          = $db.Name
                        Status            = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Remove-DbaAgDatabase
                }
            }
        }
    }

    @{ __w4045State = @{ database = $Database; shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Database $AvailabilityGroup $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__boundDatabase $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
