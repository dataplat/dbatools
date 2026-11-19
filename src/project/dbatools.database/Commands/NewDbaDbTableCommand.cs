#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a table in one or more databases. Port of public/New-DbaDbTable.ps1 (631 lines); the
/// workflow remains a module-scoped PowerShell compatibility hop.
///
/// PROCESS-ONLY, one hop. $InputObject is ValueFromPipeline, so process fires per piped database.
/// This row has the LARGEST parameter surface in the satellite: 58 parameters, 40 positional, 18
/// switches, a dozen SMO enum types, and Alias("Table") on -Name.
///
/// THE DEFINING CLASS HERE IS $PSBoundParameters PROJECTION, and it is the fail-dangerous variant.
/// Source :512 iterates the CALLER's bound parameters and assigns them straight onto the SMO Table:
///
///     foreach ($param in $PSBoundParameters.Keys) {
///         if ($param -notin $excludeParams) { $object.$param = $PSBoundParameters[$param] }
///     }
///
/// Inside a hop, $PSBoundParameters is the HOP SCRIPTBLOCK's own bindings - it would contain the
/// plumbing ($__realCmdlet, $__boundWhatIf, the boundness flags) and every parameter passed
/// positionally as $null for properties the user never supplied. A naive hop would therefore null
/// out dozens of real SMO properties and then hard-fail on "$object.__realCmdlet". The C# side
/// passes MyInvocation.BoundParameters - the caller's REAL table - and the hop preamble substitutes
/// it for $PSBoundParameters before the dot-sourced body, so the body sees exactly what the source
/// sees. Same remedy as Invoke-DbaDbTransfer (W2-136), which met this class first.
///
/// NOTE the severity split between the two variants, because it decides how much to trust a clean
/// review: W2-136 filters with an ALLOW list ($key -in $newTransferParams), so stray hop keys are
/// harmlessly dropped and a naive port can still appear to work. This row filters with an EXCLUDE
/// list, so every stray key is actively assigned. Allow-list is fail-safe; exclude-list is
/// fail-dangerous. Do not generalise a clean result from one to the other.
///
/// ONLY 10 PARAMETERS CROSS THE HOP, NOT 58. The process body references just nine parameters BY
/// NAME (SqlInstance, SqlCredential, Database, Name, Schema, ColumnMap, ColumnObject, Passthru,
/// InputObject) - verified by AST, not by reading. The other 49 exist solely to be projected, and
/// they reach the body through the carried bound-parameter table instead. Passing all 58 would add
/// 48 needless DEF-005 positions to keep aligned for no behavioural gain.
///
/// $EnableException is the tenth, and it is NOT optional even though the AST reports it unreferenced:
/// Stop-Function's -EnableException parameter DEFAULTS to $EnableException read from its CALLER's
/// scope, so if the hop does not define it, argument transformation throws ("Cannot convert value
/// \"\" to type System.Boolean") before Stop-Function ever runs. Measured the hard way - that exact
/// failure produced a false FAIL in migration/logs/probe-20260718-latch-sentinel.
///
/// THE 58 C# PROPERTIES ARE GENERATED FROM THE BASELINE, not transcribed, with defaults read from
/// the source param block (the baseline does not record defaults - the W2-141 lesson, where reading
/// a position dump lost a type and three defaults). At 58 parameters, hand-typing is where the
/// errors live.
///
/// FIVE Test-Bound SITES BECOME CARRIED CALLER-BOUNDNESS FLAGS: SqlInstance and Database and Name
/// (:465-466), Name again (:473), and Schema (:480). The Schema flag is load-bearing rather than
/// cosmetic: :480 lets a parsed two-part -Name like "[dbo].[t1]" override -Schema ONLY when the
/// caller did not pass -Schema explicitly, so a value test would silently let the parsed schema win
/// over an explicit one.
///
/// NO INTERRUPT BRIDGE: the guards at :467 and :476 and :483 are non-Continue and do set the latch,
/// but this source has NO Test-FunctionInterrupt to read it back, so they re-warn per record.
/// FOUR CROSS-RECORD CARRIES - all load-bearing, DO NOT REMOVE. An earlier version of this comment
/// asserted "no cross-record carry", which was wrong twice over and is exactly how compatibility
/// state gets deleted by a later reader who trusts the doc over the code:
///   $Name and $Schema (:481, :483) - rewritten by the two-part-name parsing. NEITHER is the
///     pipeline-bound parameter (only $InputObject is), so the binder never rewrites them and the
///     SOURCE keeps the parsed values for every later record. Reachable divergence: with
///     -Name "[my.table]", record 1 parses to the bracket-quoted "my.table"; the source's record 2
///     re-parses that UNQUOTED value as schema "my" + table "table" and creates the table in the
///     WRONG SCHEMA, while a fresh hop scope would re-parse the original and get it right. The port
///     must reproduce the source, so both carry.
///   $object (:503) and $schemaObject (:586) - read by the catch cleanup at :617-626 which calls
///     .Drop() on them; a throw before assignment leaves the SOURCE holding the previous record's
///     objects and dropping those.
/// What genuinely does NOT carry: ":490 $InputObject +=" targets the pipeline-bound parameter, which
/// IS rebound per record, and $commonParams (:507) is reset in-block.
/// NO preference assignment (checked with the unanchored pattern) and NO .IsPresent sites.
///
/// The 18 switches cross as SwitchParameter OBJECTS received untyped per B's combined rule; only
/// -Passthru is read by name in the body, but the projection reads the rest out of the bound table
/// where their SwitchParameter-ness is what the source would have assigned to the SMO property.
///
/// STREAMING, NOT BUFFERED (DEF-001): tables are created per database and -Passthru emits each one,
/// so a buffered hop would discard the record of tables already created when a later database's
/// failure terminated the hop under -EnableException.
///
/// The one $Pscmdlet.ShouldProcess gate at :496 routes to the real cmdlet via $__realCmdlet. In-hop
/// Stop-Function/Write-Message calls carry -FunctionName. Positions 0-39 are made explicit and were
/// confirmed against the exported baseline. Surface pinned by migration/baselines/New-DbaDbTable.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbTable", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed partial class NewDbaDbTableCommand : DbaBaseCmdlet
{

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // The CALLER's real bound parameters. The body projects these onto the SMO Table
        // (foreach ($param in $PSBoundParameters.Keys) { $object.$param = ... }), so it must see what the
        // user typed - not the hop scriptblock's own bindings.
        // MyInvocation.BoundParameters is EMPTY in this cmdlet's ProcessRecord (measured, W2-151 /
        // CD-0720-42: -IsNode supplied yet keys=[]), which silently starved the projection so IsNode/IsEdge
        // and every other projected property were skipped. Reconstruct the supplied-parameter set from the
        // cmdlet's own parameter properties instead - see BuildCallerBoundParameters.
        Hashtable boundParameters = BuildCallerBoundParameters();

        // Streaming, not buffered (DEF-001): tables are created per database and -Passthru emits
        // each one, so a buffered hop would drop the audit trail of tables already created.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDbTableProcess"))
            {
                _state = sentinel["__newDbaDbTableProcess"] as Hashtable;
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
            SqlInstance, SqlCredential, Database, Name, Schema, ColumnMap, ColumnObject,
            Passthru, InputObject, EnableException, boundParameters, _state,
            boundParameters.ContainsKey("SqlInstance"),
            boundParameters.ContainsKey("Database"),
            boundParameters.ContainsKey("Name"),
            boundParameters.ContainsKey("Schema"),
            this,
            // WhatIf/Confirm only, and both come back null: MyInvocation.BoundParameters is empty
            // for this cmdlet, so the hop's single ShouldProcess gate routes through $__realCmdlet,
            // which reads the outer cmdlet's real WhatIf/Confirm preference.
            // Verbose/Debug/ErrorAction/WarningAction are carried EXACTLY via EffectivePreference
            // below, not collapsed to a bool.
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            EffectivePreference("VerbosePreference"), EffectivePreference("DebugPreference"),
            EffectivePreference("ErrorActionPreference"), EffectivePreference("WarningPreference"));
    }

    // Carries the caller's EXACT effective preference (as a string the hop assigns to its preference
    // variable), reproducing what the source function's inner commands inherit. Empty
    // MyInvocation.BoundParameters could not tell that -ErrorAction/-WarningAction were passed and
    // collapsed -Verbose/-Debug to a bool, losing Stop/Inquire/Ignore; the effective preference keeps
    // every value (-Verbose sets VerbosePreference=Continue, -ErrorAction Stop sets Stop, etc.).
    private object? EffectivePreference(string preferenceVariable)
    {
        return GetVariableValue(preferenceVariable, null) is ActionPreference p ? (object)p.ToString() : null;
    }

    // Reconstructs the caller's supplied-parameter set without MyInvocation.BoundParameters, which is empty
    // in this cmdlet's ProcessRecord (measured, W2-151 / CD-0720-42). A SwitchParameter is "supplied" iff
    // IsPresent; any other parameter is "supplied" iff its value differs from a freshly constructed
    // instance's default. This reproduces exactly what $PSBoundParameters gave the source function: the keys
    // drive the SMO-Table property projection, and ContainsKey(...) drives the default-replication gates.
    // A value explicitly set to its own default reads as "not supplied", but re-projecting that default is a
    // no-op, so behaviour is unchanged. Common parameters (WhatIf/Confirm/Verbose/Debug) are not properties
    // on this class and are handled separately via BoundCommonParameter / the $__realCmdlet gate route.
    private Hashtable BuildCallerBoundParameters()
    {
        // Real boundness: _bound holds exactly the parameters the binder supplied (recorded by their
        // setters). This projects an explicit value even when it equals a default (-Schema dbo,
        // -MaximumDegreeOfParallelism 0) and an explicit -Switch:$false - none of which value inference
        // against a fresh instance could distinguish from "not supplied".
        Hashtable result = new Hashtable(StringComparer.OrdinalIgnoreCase);
        foreach (string name in _bound)
        {
            System.Reflection.PropertyInfo? prop = GetType().GetProperty(name);
            if (prop != null && prop.CanRead)
                result[name] = prop.GetValue(this);
        }
        return result;
    }
}
