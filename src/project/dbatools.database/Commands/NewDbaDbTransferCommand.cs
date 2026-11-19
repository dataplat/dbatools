#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Builds an SMO Transfer object describing a database-to-database copy. Port of
/// public/New-DbaDbTransfer.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// THE FIRST THREE-BLOCK ROW IN THIS SATELLITE: begin (:151-153), process (:154-171) and end
/// (:172-272), which changes the carry shape rather than just adding a hop. All three hops get fresh
/// scopes, so anything one block establishes for another must be carried explicitly.
///
/// $objectCollection IS A begin -> process -> end ACCUMULATOR. It is created ONCE in begin (:152) as
/// a System.Collections.ArrayList, mutated per record in process (:168, "$objectCollection.Add($object)"),
/// and consumed in end (:188, "foreach ($object in $objectCollection)"). It therefore has to ride
/// begin into process, survive every record, and reach end intact. Because it is an ArrayList, the
/// carried value is the same INSTANCE and .Add() accumulates naturally through the shared reference -
/// but the carry itself is still explicit, and end receives it rather than rebuilding it.
///
/// A TOOLING BLIND SPOT, RECORDED RATHER THAN LEFT IMPLIED: migration/tools/Find-AccumulatorCarry.ps1
/// reports NOTHING for this row. It detects "+=" targets, and this accumulates by METHOD CALL on an
/// ArrayList - no "+=" exists. Find-ConditionalCarry.ps1 does not cover it either, since that reasons
/// about assignment PLACEMENT, not mutation through a reference. This is the second known blind spot
/// in that pair, after the preference-variable class on W2-149. A clean tool run is not a clean row.
///
/// NO ShouldProcess GATE AT ALL. The source declares no SupportsShouldProcess - it carries a
/// SuppressMessage for PSUseShouldProcessForStateChangingFunctions instead - so there is no gate to
/// route and no $__realCmdlet parameter, and the C# cmdlet declares no SupportsShouldProcess either.
///
/// NO INTERRUPT BRIDGE: this source contains NO Test-FunctionInterrupt, so the non-Continue guards in
/// process (:156, :160, :165) and end (:176, :180, :183) simply re-evaluate. Note the end block runs
/// ONCE per invocation regardless, so its guards fire once by construction.
///
/// FIVE Test-Bound SITES BECOME CARRIED CALLER-BOUNDNESS FLAGS, SPLIT ACROSS TWO BLOCKS: SqlInstance
/// (:155) and Database (:159) in process; DestinationDatabase (:225), SchemaOnly (:268) and DataOnly
/// (:269) in end. The last two are load-bearing rather than cosmetic - they gate
/// "$transfer.CopyData = -not $SchemaOnly" and "$transfer.CopySchema = -not $DataOnly", so BOUNDNESS,
/// not truthiness, decides whether the property is touched at all. Passing -SchemaOnly:$false is
/// therefore different from omitting it, which a value test would collapse.
///
/// DEF-007 BIND-TIME DEFAULT: "$DestinationDatabase = $Database" (:133) derives one parameter's
/// default from another, which a C# property initializer cannot express. It is resolved at bind time
/// in the hop, and its boundness flag at :225 still reflects what the CALLER passed rather than the
/// derived value - otherwise the "Initial Catalog" fallback at :225 would stop firing.
///
/// POSITIONS 0-10, with the three switches unpositioned. Recorded here because I first got this
/// WRONG in the opposite direction and the surface diff caught it. My baseline dump read
/// "$_.sets.__AllParameterSets.position" and printed every position EMPTY, so I concluded the
/// command had none and shipped a port with no Position attributes; the compiled surface diff then
/// reported ELEVEN Breaking findings. The cause is that this command declares
/// DefaultParameterSetName = "Default", so its parameters live under a set named "Default" and
/// __AllParameterSets does not exist - the dump was reading a null. THE LESSON IS NOT "confirm
/// against the baseline", which I did; it is that a baseline READER must resolve the actual set name
/// rather than assume __AllParameterSets, because the wrong lookup fails SILENTLY as an empty value
/// that looks like a legitimate answer.
///
/// -SqlInstance and -DestinationSqlInstance are SINGULAR DbaInstanceParameter, not arrays. -CopyAll
/// carries a 30-value ValidateSet, preserved verbatim. The three switches (CopyAllObjects,
/// SchemaOnly, DataOnly) and the inherited EnableException cross as SwitchParameter OBJECTS received
/// untyped, per B's combined rule. In-hop Stop-Function calls carry -FunctionName. The command
/// returns an Smo.Transfer, declared via OutputType. Surface pinned by
/// migration/baselines/New-DbaDbTransfer.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbTransfer", DefaultParameterSetName = "Default")]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.Transfer))]
public sealed partial class NewDbaDbTransferCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The destination SQL Server instance.</summary>
    [Parameter(Position = 2)]
    public DbaInstanceParameter? DestinationSqlInstance { get; set; }

    /// <summary>Alternative credential for the destination instance.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>The source database.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? Database { get; set; }

    /// <summary>The destination database; defaults to the source database at bind time.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? DestinationDatabase { get; set; }

    /// <summary>Bulk copy batch size.</summary>
    [Parameter(Position = 6)]
    public int BatchSize { get; set; } = 50000;

    /// <summary>Bulk copy timeout in seconds.</summary>
    [Parameter(Position = 7)]
    public int BulkCopyTimeOut { get; set; } = 5000;

    /// <summary>Scripting options applied to the transfer.</summary>
    [Parameter(Position = 8)]
    public Microsoft.SqlServer.Management.Smo.ScriptingOptions? ScriptingOption { get; set; }

    /// <summary>SMO objects to transfer, piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 9)]
    public Microsoft.SqlServer.Management.Smo.NamedSmoObject[]? InputObject { get; set; }

    /// <summary>Transfer every object in the database.</summary>
    [Parameter]
    public SwitchParameter CopyAllObjects { get; set; }

    /// <summary>Object categories to transfer wholesale.</summary>
    [Parameter(Position = 10)]
    [ValidateSet("FullTextCatalogs", "FullTextStopLists", "SearchPropertyLists", "Tables",
        "Views", "StoredProcedures", "UserDefinedFunctions", "UserDefinedDataTypes", "UserDefinedTableTypes",
        "PlanGuides", "Rules", "Defaults", "Users", "Roles", "PartitionSchemes", "PartitionFunctions",
        "XmlSchemaCollections", "SqlAssemblies", "UserDefinedAggregates", "UserDefinedTypes", "Schemas",
        "Synonyms", "Sequences", "DatabaseTriggers", "DatabaseScopedCredentials", "ExternalFileFormats",
        "ExternalDataSources", "Logins", "ExternalLibraries")]
    [PsStringArrayCast]
    public string[]? CopyAll { get; set; }

    /// <summary>Transfer schema only; suppresses data copy.</summary>
    [Parameter]
    public SwitchParameter SchemaOnly { get; set; }

    /// <summary>Transfer data only; suppresses schema copy.</summary>
    [Parameter]
    public SwitchParameter DataOnly { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The $objectCollection ArrayList, carried begin -> process -> end; opaque to C#.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDbTransferBegin"))
            {
                _state = sentinel["__newDbaDbTransferBegin"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            EnableException, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDbTransferProcess"))
            {
                _state = sentinel["__newDbaDbTransferProcess"] as Hashtable;
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
            SqlInstance, Database, InputObject, EnableException, _state,
            MyInvocation.BoundParameters.ContainsKey("SqlInstance"),
            MyInvocation.BoundParameters.ContainsKey("Database"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        // Streaming, not buffered (DEF-001): the end block emits the Transfer object it built, and a
        // buffered hop would discard output already produced if a later statement terminated the hop
        // under -EnableException.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, EndScript,
            SqlInstance, SqlCredential, DestinationSqlInstance, DestinationSqlCredential,
            Database, DestinationDatabase, BatchSize, BulkCopyTimeOut, ScriptingOption,
            CopyAllObjects, CopyAll, SchemaOnly, DataOnly, EnableException, _state,
            MyInvocation.BoundParameters.ContainsKey("DestinationDatabase"),
            MyInvocation.BoundParameters.ContainsKey("SchemaOnly"),
            MyInvocation.BoundParameters.ContainsKey("DataOnly"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
}
