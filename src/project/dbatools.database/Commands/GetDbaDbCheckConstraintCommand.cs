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

/// <summary>Gets database Check constraints.</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbCheckConstraint")]
public sealed class GetDbaDbCheckConstraintCommand : DbaInstanceCmdlet
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

    /// <summary>Exclude check constraints on system tables.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemTable { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;
            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;

            // The source finishes its accessible-database selection before emitting checks.
            // Pinned help documents wildcards for -Database only, which the source's literal -In
            // never honoured; a real database name of this instance stays literal, and
            // -ExcludeDatabase stays literal.
            WildcardNameMatcher databaseMatcher = NativeDatabaseSelection.CreateInOperandMatcher(Database, true,
                NativeDatabaseSelection.DatabaseNames(server));
            List<SmoDatabase> selected = new();
            foreach (SmoDatabase candidate in server.Databases)
            {
                if (Interrupted)
                    return;
                if (candidate.IsAccessible &&
                    (!LanguagePrimitives.IsTrue(Database) || databaseMatcher.Matches(candidate.Name)) &&
                    (!LanguagePrimitives.IsTrue(ExcludeDatabase) || !NativeDatabaseSelection.ContainsInOperand(ExcludeDatabase, candidate.Name)))
                    selected.Add(candidate);
            }
            foreach (SmoDatabase database in selected)
            {
                if (Interrupted)
                    return;
                if (!database.IsAccessible)
                {
                    WriteMessage(MessageLevel.Warning, String.Format("Database {0} is not accessible. Skipping.", database));
                    continue;
                }
                WriteChecks(server, database, instance);
            }
        }
    }

    private void WriteChecks(Server server, SmoDatabase database, DbaInstanceParameter instance)
    {
        foreach (Table table in database.Tables)
        {
            if (Interrupted)
                return;
            // The source tests boundness, so -ExcludeSystemTable:$false still excluded system
            // tables; the switch value decides here, so an explicit false behaves like absent.
            if (ExcludeSystemTable.IsPresent && table.IsSystemObject)
                continue;
            if (table.Checks.Count == 0)
            {
                WriteMessage(MessageLevel.Verbose,
                    String.Format("No Checks exist in {0} table on the {1} database on {2}", table, database, instance), table);
                continue;
            }
            foreach (Check check in table.Checks)
            {
                if (Interrupted)
                    return;
                PSObject result = PSObject.AsPSObject(check);
                foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database", "DatabaseId" })
                    result.Properties.Remove(property);
                OutputHelper.AddInstanceProperties(result, server);
                result.Properties.Add(new PSNoteProperty("Database", database.Name));
                result.Properties.Add(new PSNoteProperty("DatabaseId", database.ID));
                OutputHelper.SetDefaultDisplayPropertySet(result,
                    "ComputerName", "InstanceName", "SqlInstance", "Database", "Parent", "ID", "CreateDate",
                    "DateLastModified", "Name", "IsEnabled", "IsChecked", "NotForReplication", "Text", "State");
                WriteObject(result);
            }
        }
    }
}
