#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves foreign key constraints from SQL Server database tables</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbForeignKey")]
public sealed class GetDbaDbForeignKeyCommand : DbaInstanceCmdlet
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

    /// <summary>Exclude system tables when this parameter is bound.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemTable { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;

            // The source materializes accessible databases before the second accessibility check.
            // Pinned help documents wildcards for -Database only, which the source's literal -In
            // never honoured; a real database name of this instance stays literal (pinned
            // Remove-DbaDbData passes one), and -ExcludeDatabase stays literal.
            WildcardNameMatcher databaseMatcher = NativeDatabaseSelection.CreateInOperandMatcher(Database, true,
                NativeDatabaseSelection.DatabaseNames(server));
            List<Microsoft.SqlServer.Management.Smo.Database> databases = new();
            foreach (Microsoft.SqlServer.Management.Smo.Database database in server.Databases)
            {
                if (!database.IsAccessible)
                    continue;
                if (LanguagePrimitives.IsTrue(Database) && !databaseMatcher.Matches(database.Name))
                    continue;
                if (LanguagePrimitives.IsTrue(ExcludeDatabase) && NativeDatabaseSelection.ContainsInOperand(ExcludeDatabase, database.Name))
                    continue;
                databases.Add(database);
            }

            foreach (Microsoft.SqlServer.Management.Smo.Database database in databases)
            {
                if (!database.IsAccessible)
                {
                    WriteMessage(MessageLevel.Warning, String.Format("Database {0} is not accessible. Skipping.", database));
                    continue;
                }

                foreach (Table table in database.Tables)
                {
                    // The source tests boundness, so -ExcludeSystemTable:$false still excluded system
                    // tables; the switch value decides here, so an explicit false behaves like absent.
                    if (ExcludeSystemTable.IsPresent && table.IsSystemObject)
                        continue;
                    if (table.ForeignKeys.Count == 0)
                    {
                        WriteMessage(MessageLevel.Verbose,
                            String.Format("No Foreign Keys exist in {0} table on the {1} database on {2}", table, database, instance), table);
                        continue;
                    }

                    foreach (ForeignKey foreignKey in table.ForeignKeys)
                    {
                        PSObject output = PSObject.AsPSObject(foreignKey);
                        foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Table" })
                            output.Properties.Remove(property);
                        OutputHelper.AddInstanceProperties(output, server);
                        output.Properties.Add(new PSNoteProperty("Database", database.Name));
                        output.Properties.Add(new PSNoteProperty("Schema", table.Schema));
                        output.Properties.Add(new PSNoteProperty("Table", table.Name));
                        OutputHelper.SetDefaultDisplayPropertySet(output,
                            "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Table", "ID", "CreateDate",
                            "DateLastModified", "Name", "IsEnabled", "IsChecked", "NotForReplication", "ReferencedKey",
                            "ReferencedTable", "ReferencedTableSchema");
                        WriteObject(output);
                    }
                }
            }
        }
    }
}
