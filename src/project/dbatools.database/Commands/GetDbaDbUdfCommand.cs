#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Retrieves user-defined functions and aggregates directly from accessible databases through SMO. Port of
// public/Get-DbaDbUdf.ps1; surface pinned by migration/baselines/Get-DbaDbUdf.json (positions 0-7,
// ExcludeSystemUdf non-positional, SqlInstance Mandatory ValueFromPipeline, no ShouldProcess). Earlier
// Claude reference: refs/fleet/imported/native-batch2 87edbc6b, c18365a1, 8786e7a4.
/// <summary>Retrieves User Defined Functions and User Defined Aggregates from SQL Server databases with filtering and metadata</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbUdf")]
public sealed class GetDbaDbUdfCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Exclude system user-defined functions from the results.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemUdf { get; set; }

    /// <summary>Filter to UDFs/aggregates in the specified schema(s).</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Schema { get; set; }

    /// <summary>Exclude UDFs/aggregates in the specified schema(s).</summary>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? ExcludeSchema { get; set; }

    /// <summary>Filter to the specified UDF/aggregate(s) by name.</summary>
    [Parameter(Position = 6)]
    [PsStringArrayCast]
    public string[]? Name { get; set; }

    /// <summary>Exclude the specified UDF/aggregate(s) by name.</summary>
    [Parameter(Position = 7)]
    [PsStringArrayCast]
    public string[]? ExcludeName { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;
            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;

            // The source completes its accessible-database selection before reading any functions.
            // Pinned help documents wildcards for -Database only, which the source's literal -In never
            // honoured; a real database name of this instance stays literal, and -ExcludeDatabase stays
            // literal.
            WildcardNameMatcher databaseMatcher = NativeDatabaseSelection.CreateInOperandMatcher(Database, true,
                NativeDatabaseSelection.DatabaseNames(server));
            List<SmoDatabase> databases = new();
            foreach (SmoDatabase candidate in server.Databases)
            {
                if (Interrupted)
                    return;
                if (candidate.IsAccessible &&
                    (!LanguagePrimitives.IsTrue(Database) || databaseMatcher.Matches(candidate.Name)) &&
                    (!LanguagePrimitives.IsTrue(ExcludeDatabase) || !NativeDatabaseSelection.ContainsInOperand(ExcludeDatabase, candidate.Name)))
                    databases.Add(candidate);
            }

            foreach (SmoDatabase database in databases)
            {
                if (Interrupted)
                    return;
                WriteFunctions(server, database, instance);
            }
        }
    }

    private void WriteFunctions(Server server, SmoDatabase database, DbaInstanceParameter instance)
    {
        // Let SMO read every referenced property in one query; this clears previously loaded properties.
        InitializeCollection(() => database.UserDefinedFunctions.ClearAndInitialize(String.Empty,
            new[] { "Schema", "Name", "CreateDate", "DateLastModified", "DataType", "IsSystemObject" }));
        // UserDefinedAggregates have no IsSystemObject property, so the source initializes them separately.
        InitializeCollection(() => database.UserDefinedAggregates.ClearAndInitialize(String.Empty,
            new[] { "Schema", "Name", "CreateDate", "DateLastModified", "DataType" }));

        List<ScriptSchemaObjectBase> functions = new();
        foreach (UserDefinedFunction function in database.UserDefinedFunctions)
        {
            // The source tests the switch's value, so -ExcludeSystemUdf:$false keeps system functions.
            if (ExcludeSystemUdf.ToBool() && function.IsSystemObject)
                continue;
            functions.Add(function);
        }
        // UserDefinedAggregates are always user-created; the source appends them after the functions.
        foreach (UserDefinedAggregate aggregate in database.UserDefinedAggregates)
            functions.Add(aggregate);

        if (functions.Count == 0)
        {
            WriteMessage(MessageLevel.Verbose,
                String.Format("No User Defined Functions or Aggregates exist in the {0} database on {1}", database, instance), database);
            return;
        }

        // Pinned help documents wildcards for -Name and -ExcludeName, which the source's literal -in and
        // -notin never honoured; a real function or aggregate name of this database stays literal, and
        // -Schema and -ExcludeSchema stay literal.
        WildcardNameMatcher nameMatcher = NativeDatabaseSelection.CreateNameMatcher(Name, true, FunctionNames(database));
        WildcardNameMatcher excludeNameMatcher = NativeDatabaseSelection.CreateNameMatcher(ExcludeName, true, FunctionNames(database));
        foreach (ScriptSchemaObjectBase function in functions)
        {
            if (Interrupted)
                return;
            if (LanguagePrimitives.IsTrue(Schema) && !NativeDatabaseSelection.ContainsName(Schema, function.Schema))
                continue;
            if (LanguagePrimitives.IsTrue(ExcludeSchema) && NativeDatabaseSelection.ContainsName(ExcludeSchema, function.Schema))
                continue;
            if (LanguagePrimitives.IsTrue(Name) && !nameMatcher.Matches(function.Name))
                continue;
            if (LanguagePrimitives.IsTrue(ExcludeName) && excludeNameMatcher.Matches(function.Name))
                continue;

            PSObject result = PSObject.AsPSObject(function);
            // Add-Member -Force replaces any note left by an earlier call on the same SMO object.
            foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database" })
                result.Properties.Remove(property);
            OutputHelper.AddInstanceProperties(result, server);
            result.Properties.Add(new PSNoteProperty("Database", database.Name));
            OutputHelper.SetDefaultDisplayPropertySet(result,
                "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "CreateDate", "DateLastModified", "Name", "DataType");
            WriteObject(result);
        }
    }

    // Every function and aggregate name of the database, before -ExcludeSystemUdf: the unfiltered scope
    // of the -Name and -ExcludeName filters.
    private static IEnumerable<string> FunctionNames(SmoDatabase database)
    {
        foreach (UserDefinedFunction function in database.UserDefinedFunctions)
            yield return function.Name;
        foreach (UserDefinedAggregate aggregate in database.UserDefinedAggregates)
            yield return aggregate.Name;
    }

    private void InitializeCollection(Action initialize)
    {
        try
        {
            initialize();
        }
        catch (Exception ex)
        {
            // PS: Write-Message -Level Verbose -Message "ClearAndInitialize failed: $_" - $_ renders the
            // method binder's MethodInvocationException text for the failed .NET call.
            WriteMessage(MessageLevel.Verbose, String.Format(
                "ClearAndInitialize failed: Exception calling \"ClearAndInitialize\" with \"2\" argument(s): \"{0}\"", ex.Message));
        }
    }
}
