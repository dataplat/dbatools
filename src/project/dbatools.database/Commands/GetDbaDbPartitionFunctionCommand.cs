#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;
using SmoPartitionFunction = Microsoft.SqlServer.Management.Smo.PartitionFunction;

namespace Dataplat.Dbatools.Commands;

// Retrieves typed SMO partition functions from accessible databases, preserving the
// pinned name filters, instance metadata and default display columns.
/// <summary>Retrieves partition function definitions and metadata from SQL Server databases.</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbPartitionFunction")]
public sealed class GetDbaDbPartitionFunctionCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to search.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Filter to the specified partition function(s) by name.</summary>
    [Parameter(Position = 4)]
    [Alias("Name")]
    [PsStringArrayCast]
    public string[]? PartitionFunction { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance);
            if (server == null)
                continue;

            List<SmoDatabase> databases = new();
            foreach (SmoDatabase database in server.Databases)
            {
                if (!database.IsAccessible)
                    continue;
                if (LanguagePrimitives.IsTrue(Database) && !NativeDatabaseSelection.ContainsInOperand(Database, database.Name))
                    continue;
                if (LanguagePrimitives.IsTrue(ExcludeDatabase) && NativeDatabaseSelection.ContainsInOperand(ExcludeDatabase, database.Name))
                    continue;
                databases.Add(database);
            }

            foreach (SmoDatabase database in databases)
            {
                if (!database.IsAccessible)
                {
                    WriteMessage(MessageLevel.Warning, String.Format("Database {0} is not accessible. Skipping.", database));
                    continue;
                }

                // Pinned help documents wildcards for -PartitionFunction, which the source's
                // literal -in never honoured; a real partition function name of this database
                // stays literal.
                WildcardNameMatcher functionMatcher = NativeDatabaseSelection.CreateNameMatcher(PartitionFunction, true,
                    FunctionNames(database));
                List<SmoPartitionFunction> functions = new();
                foreach (SmoPartitionFunction function in database.PartitionFunctions)
                {
                    if (LanguagePrimitives.IsTrue(PartitionFunction) && !functionMatcher.Matches(function.Name))
                        continue;
                    functions.Add(function);
                }
                // Upstream tests !$partitionfunctions. An unfiltered SMO collection is an ICollection,
                // not an IList, so PowerShell treats it as true even when empty; only an empty
                // filtered pipeline result ($null) reaches the message.
                if (functions.Count == 0 && LanguagePrimitives.IsTrue(PartitionFunction))
                {
                    WriteMessage(MessageLevel.Verbose, String.Format("No Partition Functions exist in the {0} database on {1}", database, instance), database);
                    continue;
                }

                foreach (SmoPartitionFunction function in functions)
                {
                    PSObject output = PSObject.AsPSObject(function);
                    foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database" })
                        output.Properties.Remove(name);
                    OutputHelper.AddInstanceProperties(output, server);
                    output.Properties.Add(new PSNoteProperty("Database", database.Name));
                    OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance",
                        "Database", "CreateDate", "Name", "NumberOfPartitions");
                    WriteObject(output);
                }
            }
        }
    }

    // Every partition function name of the database, the unfiltered scope of the name filter.
    private static IEnumerable<string> FunctionNames(SmoDatabase database)
    {
        foreach (SmoPartitionFunction function in database.PartitionFunctions)
            yield return function.Name;
    }
}
