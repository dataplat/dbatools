#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Analyzes table and index compression savings. Port of
/// public/Test-DbaDbCompression.ps1 (W1-126). BeginProcessing constructs the source SQL
/// filters once and returns them through private non-emitted carriers. The full per-record
/// analysis body rides one module-scoped PowerShell hop so the large SQL batch, SMO/ETS
/// reads, private-command mocks, dynamic continues, DbaSize coercion, and result shaping
/// retain PowerShell semantics. The source's stale $db local is carried across pipeline
/// ProcessRecord calls because it is read as an error target before reassignment.
/// Surface pinned by migration/baselines/Test-DbaDbCompression.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaDbCompression", DefaultParameterSetName = "Default")]
public sealed partial class TestDbaDbCompressionCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Databases to analyze.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>Databases to exclude.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Schemas to analyze.</summary>
    [Parameter(Position = 4)]
    public string[]? Schema { get; set; }

    /// <summary>Tables to analyze.</summary>
    [Parameter(Position = 5)]
    public string[]? Table { get; set; }

    /// <summary>Maximum number of ranked objects per database.</summary>
    [Parameter(Position = 6)]
    public int ResultSize { get; set; }

    /// <summary>Ranking measure for ResultSize.</summary>
    [Parameter(Position = 7)]
    [PsStringCast]
    [ValidateSet("TotalPages", "UsedPages", "TotalRows")]
    public string Rank { get; set; } = "TotalPages";

    /// <summary>Granularity of ResultSize filtering.</summary>
    [Parameter(Position = 8)]
    [PsStringCast]
    [ValidateSet("Partition", "Index", "Table")]
    public string FilterBy { get; set; } = "Partition";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _sqlSchemaWhere;
    private object? _sqlTableWhere;
    private object? _sqlRestrict;
    private object? _staleDatabase;
    private bool _staleDatabaseAssigned;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Schema, Table, ResultSize, Rank, FilterBy, BoundParameterNames(),
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (IsCarrier(item, BeginCarrierMarker))
            {
                _sqlSchemaWhere = item!.Properties["SqlSchemaWhere"]?.Value;
                _sqlTableWhere = item.Properties["SqlTableWhere"]?.Value;
                _sqlRestrict = item.Properties["SqlRestrict"]?.Value;
            }
            else
            {
                WriteObject(item);
            }
        }
    }

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (IsCarrier(item, ProcessCarrierMarker))
            {
                _staleDatabase = item!.Properties["StaleDatabase"]?.Value;
                _staleDatabaseAssigned = LanguagePrimitives.IsTrue(item!.Properties["StaleDatabaseAssigned"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase,
            TestBound("ExcludeDatabase"), _sqlSchemaWhere, _sqlTableWhere, _sqlRestrict,
            _staleDatabase, _staleDatabaseAssigned, EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private string[] BoundParameterNames()
    {
        List<string> names = new();
        foreach (string name in MyInvocation.BoundParameters.Keys)
            names.Add(name);
        return names.ToArray();
    }

    private static bool IsCarrier(PSObject? item, string marker)
    {
        return item?.Properties[marker] is not null &&
               LanguagePrimitives.IsTrue(item.Properties[marker].Value);
    }
}
