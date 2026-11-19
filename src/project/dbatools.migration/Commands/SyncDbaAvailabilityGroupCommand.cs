#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies the server-level objects an availability group does not replicate - logins, agent jobs,
/// linked servers, credentials and the rest - from the primary replica to every secondary. Port of
/// public/Sync-DbaAvailabilityGroup.ps1; the workflow stays a module-scoped PowerShell compatibility
/// hop because every step is a call to another dbatools command plus SMO refreshes on the JobServer.
/// Surface pinned by migration/baselines/Sync-DbaAvailabilityGroup.json.
///
/// PROCESS+END lifecycle split. InputObject is ValueFromPipeline, so process fires once per piped
/// availability group and collects primary/secondary pairs; the end block does the whole sync once,
/// after every record has been seen. Folding end into process would sync per record, which is the
/// exact duplication the source's $dupe check exists to prevent.
///
/// NO BEGIN HOP, and the two things begin does are reproduced where they are actually read.
/// "$allcombos = @()" is the accumulator seeded in C# below - an empty array is not worth a runspace
/// round trip, and a begin hop that produced nothing observable would be evidence-free. The other
/// statement, "if ($Force) { $ConfirmPreference = 'none' }", is a preference variable: begin, process
/// and end share ONE function scope in the source, so the assignment reaches the end block's
/// ShouldProcess call and the confirmation gates of the nested Copy-Dba* commands. The hop scopes are
/// separate, so it is repeated at the top of the end hop, which is the scope that reads it.
///
/// THREE VALUES CROSS RECORDS, and only one of them is an accumulator the source names as such.
///   $allcombos   - the primary/secondary pairs. Grown per record, consumed by end.
///   $Secondary   - a PARAMETER variable the process body reassigns: "$Secondary += (replica names)".
///                  It is not pipeline-bound, so the engine never rebinds it, and record two starts
///                  from record one's accumulated list. Its param-block type constraint survives the
///                  carry because the inner param() redeclares it, so the value coerces exactly as
///                  the function-world assignment would.
///   $secondaries - only assigned INSIDE "if ($Secondary)", so a record that resolves no secondary
///                  keeps the previous record's connected servers and files them into its own combo.
/// All three ride one process sentinel. One Seeded flag covers $Secondary and $secondaries together:
/// after any record has run, the carried value is the correct one for the next: only the
/// no-record-has-run case may fall back to the bound argument.
///
/// $InputObject IS NOT CARRIED, deliberately. The body does "$InputObject += Get-DbaAvailabilityGroup"
/// too, but the engine rebinds a pipeline-bound parameter on every record, which discards the
/// previous record's append. Carrying it would invent an accumulation the source does not have.
///
/// THE INTERRUPT LATCH IS SEEDED, NOT GUARDED. There is no Interrupted prologue on ProcessRecord:
/// the source's process block reads Test-FunctionInterrupt nowhere, and adding the guard is the #723
/// over-application that silences every record behind a mid-pipe failure. The end block DOES read it,
/// so the flag is carried out of each process hop (sticky, because the seed goes back in on the next
/// record) and seeded into the end hop, where the source's own "if (Test-FunctionInterrupt) { return }"
/// performs the stop.
///
/// TEST-BOUND BECOMES CARRIED FLAGS. The hop passes every argument positionally, so an uncarried
/// Test-Bound would report the whole parameter list bound and neither guard would ever fire; the
/// dot-sourced body compounds it with a fresh empty $PSBoundParameters. The three sites - the
/// "-Primary or an Input Object" guard and the two -Job/-ExcludeJob splat keys - read booleans
/// computed from the cmdlet's own MyInvocation.BoundParameters instead.
///
/// -WhatIf AND -Confirm ARE CARRIED INTO THE END HOP. Only the DatabaseOwner step consults
/// ShouldProcess directly (routed through $__realCmdlet); the other fourteen steps are bare calls to
/// Copy-Dba* commands that declare their own SupportsShouldProcess and, in the function world,
/// inherited $WhatIfPreference from the caller's scope. A hop scope does not inherit it, so without
/// this carry a -WhatIf run would perform a real sync - the same defect W6-026 measured on
/// Start-DbaMigration. Splatting the bound values into the hop's [CmdletBinding(SupportsShouldProcess)]
/// block reproduces the inheritance.
///
/// NAMED-WRAPPER SHIM ON THE END BODY. It calls Write-ProgressHelper fifteen times and that helper
/// reads (Get-PSCallStack)[1].Command; run bare the frame reads as a scriptblock marker. The body
/// therefore runs inside a function carrying the command's name, dot-invoked so its two early returns
/// leave the body rather than the hop and its locals stay visible to the scope the latch lives in.
///
/// Switches marshal as real booleans and the inner param leaves them untyped: PowerShell excludes
/// [switch] parameters from positional binding, so one typed flag would shift every argument after it.
/// The body reads them as booleans and splices them with -Switch:$Value, which a boolean serves.
/// </summary>
[Cmdlet(VerbsData.Sync, "DbaAvailabilityGroup", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed partial class SyncDbaAvailabilityGroupCommand : DbaBaseCmdlet
{
    /// <summary>The primary replica the server-level objects are copied from.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? Primary { get; set; }

    /// <summary>Login to the primary replica using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? PrimarySqlCredential { get; set; }

    /// <summary>The secondary replicas the objects are copied to. Discovered from the availability group when omitted.</summary>
    [Parameter(Position = 2)]
    public DbaInstanceParameter[]? Secondary { get; set; }

    /// <summary>Login to the secondary replicas using alternative credentials.</summary>
    [Parameter(Position = 3)]
    public PSCredential? SecondarySqlCredential { get; set; }

    /// <summary>Windows credential used to decrypt passwords over PowerShell remoting.</summary>
    [Parameter(Position = 4)]
    public PSCredential? Credential { get; set; }

    /// <summary>The availability group whose replicas are synchronized.</summary>
    [Parameter(Position = 5)]
    public string? AvailabilityGroup { get; set; }

    /// <summary>Object types to leave out of the synchronization.</summary>
    [Parameter(Position = 6)]
    [Alias("ExcludeType")]
    [ValidateSet("AgentCategory", "AgentOperator", "AgentAlert", "AgentProxy", "AgentSchedule", "AgentJob",
        "Credentials", "CustomErrors", "DatabaseMail", "DatabaseOwner", "LinkedServers", "Logins",
        "LoginPermissions", "SpConfigure", "SystemTriggers")]
    public string[]? Exclude { get; set; }

    /// <summary>Only synchronize these logins.</summary>
    [Parameter(Position = 7)]
    public string[]? Login { get; set; }

    /// <summary>Skip these logins.</summary>
    [Parameter(Position = 8)]
    public string[]? ExcludeLogin { get; set; }

    /// <summary>Only synchronize these SQL Agent jobs.</summary>
    [Parameter(Position = 9)]
    public string[]? Job { get; set; }

    /// <summary>Skip these SQL Agent jobs.</summary>
    [Parameter(Position = 10)]
    public string[]? ExcludeJob { get; set; }

    /// <summary>Disable the synchronized jobs on the secondary replicas.</summary>
    [Parameter]
    public SwitchParameter DisableJobOnDestination { get; set; }

    /// <summary>Availability groups from Get-DbaAvailabilityGroup.</summary>
    [Parameter(Position = 11, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]? InputObject { get; set; }

    /// <summary>Copy credentials, mail accounts and linked servers without their passwords.</summary>
    [Parameter]
    public SwitchParameter ExcludePassword { get; set; }

    /// <summary>Drop and recreate objects that already exist on the secondaries.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The lifecycle overrides and the two hop scripts live in the .Script.cs sibling so neither
    // half runs past the 400-line file rule.

    // $allcombos, the reassigned $Secondary, $secondaries and the interrupt latch. Seeded here rather
    // than by a begin hop; AllCombos starts as begin's "$allcombos = @()".
    private Hashtable _processState = new Hashtable
    {
        ["AllCombos"] = new object[0],
        ["Secondary"] = null,
        ["Secondaries"] = null,
        ["Seeded"] = false,
        ["Interrupted"] = false
    };

}
