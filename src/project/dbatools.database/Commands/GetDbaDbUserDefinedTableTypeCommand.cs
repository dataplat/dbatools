#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves user-defined table types from SQL Server databases</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbUserDefinedTableType")]
public sealed class GetDbaDbUserDefinedTableTypeCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
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

    /// <summary>Filter to the specified user-defined table type(s) by name.</summary>
    [Parameter(Position = 4)]
    public string[]? Type { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted || !TestBound(nameof(SqlInstance)))
            return;

        // These object arrays bind to Get-DbaDatabase's string-array parameters upstream.
        // Pinned help documents wildcards for -Database and -ExcludeDatabase, which the exact-match
        // Get-DbaDatabase call never honoured.
        foreach (Microsoft.SqlServer.Management.Smo.Database database in NativeDatabaseSelection.GatherAccessible(
            this, SqlInstance, SqlCredential, Database, ExcludeDatabase,
            server => SetActiveConnection(server.ConnectionContext),
            message => WriteMessage(MessageLevel.Warning, message), () => Interrupted))
        {
            if (database.UserDefinedTableTypes.Count == 0)
            {
                // The pinned command has no instance variable in this scope.
                WriteMessage(MessageLevel.Output, String.Format("No User Defined Table Types exist in the {0} database on ", database), database);
                continue;
            }

            foreach (UserDefinedTableType tableType in database.UserDefinedTableTypes)
            {
                if (Interrupted)
                    return;
                if (LanguagePrimitives.IsTrue(Type) && !NativeDatabaseSelection.ContainsName(Type, tableType.Name))
                    continue;
                // IsSystemObject is optional adapter metadata, not a UserDefinedTableType CLR property.
                if (LanguagePrimitives.IsTrue(SmoServerExtensions.GetPSProperty(tableType, "IsSystemObject")))
                    continue;

                PSObject output = PSObject.AsPSObject(tableType);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database" })
                    output.Properties.Remove(name);
                OutputHelper.AddInstanceProperties(output, database.Parent);
                output.Properties.Add(new PSNoteProperty("Database", database.Name));
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "InstanceName", "SqlInstance", "Database", "ID", "Name", "Columns",
                    "Owner", "CreateDate", "IsSystemObject", "Version");
                WriteObject(output);
            }
        }
    }
}
