#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo.Broker;

namespace Dataplat.Dbatools.Commands;

/// <summary>Gets database service broker queues</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbServiceBrokerQueue")]
public sealed class GetDbaDbServiceBrokerQueueCommand : DbaInstanceCmdlet
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

    /// <summary>Exclude system Service Broker queues from the results.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemQueue { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted || !TestBound(nameof(SqlInstance)))
            return;

        // The pinned Get-DbaDatabase call binds these object arrays to string arrays.
        // Pinned help documents wildcards for -Database and -ExcludeDatabase, which the exact-match
        // Get-DbaDatabase call never honoured.
        foreach (Microsoft.SqlServer.Management.Smo.Database database in NativeDatabaseSelection.GatherAccessible(
            this, SqlInstance, SqlCredential, Database, ExcludeDatabase,
            server => SetActiveConnection(server.ConnectionContext),
            message => WriteMessage(MessageLevel.Warning, message), () => Interrupted))
        {
            if (database.ServiceBroker.Queues.Count == 0)
            {
                // The pinned command has no instance variable in this scope.
                WriteMessage(MessageLevel.Output, String.Format("No Service Broker Queues exist in the {0} database on ", database), database);
                continue;
            }

            foreach (ServiceQueue queue in database.ServiceBroker.Queues)
            {
                if (Interrupted)
                    return;
                // Upstream tests boundness, so an explicitly false switch still excluded system
                // queues; the switch value decides here, so an explicit false behaves like absent.
                if (ExcludeSystemQueue.IsPresent && queue.IsSystemObject)
                    continue;

                PSObject output = PSObject.AsPSObject(queue);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database", "QueueID" })
                    output.Properties.Remove(name);
                OutputHelper.AddInstanceProperties(output, database.Parent);
                output.Properties.Add(new PSNoteProperty("Database", database.Name));
                OutputHelper.AddAliasProperty(output, "QueueID", "ID");
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "QueueID",
                    "CreateDate", "DateLastModified", "Name", "ProcedureName", "ProcedureSchema");
                WriteObject(output);
            }
        }
    }
}
