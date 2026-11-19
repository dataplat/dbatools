#nullable enable

using System;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo.Broker;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves Service Broker services from SQL Server databases for auditing and troubleshooting messaging configurations</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbServiceBrokerService")]
public sealed class GetDbaDbServiceBrokerServiceCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Exclude system Service Broker services from the results.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemService { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted || !TestBound(nameof(SqlInstance)))
            return;

        // These object-array parameters bind to Get-DbaDatabase's literal string-array filters.
        string[]? include = Database is null ? null :
            (string[])LanguagePrimitives.ConvertTo(Database, typeof(string[]), CultureInfo.InvariantCulture);
        string[]? exclude = ExcludeDatabase is null ? null :
            (string[])LanguagePrimitives.ConvertTo(ExcludeDatabase, typeof(string[]), CultureInfo.InvariantCulture);
        foreach (SmoDatabase database in NativeDatabaseSelection.Gather(this, SqlInstance, SqlCredential,
            include, exclude, server => SetActiveConnection(server.ConnectionContext), () => Interrupted))
        {
            if (Interrupted)
                return;
            if (!database.IsAccessible)
            {
                WriteMessage(MessageLevel.Warning, String.Format("Database {0} is not accessible. Skipping.", database));
                continue;
            }
            if (database.ServiceBroker.Services.Count == 0)
            {
                // The source's instance variable is unset in this branch.
                WriteMessage(MessageLevel.Output,
                    String.Format("No Service Broker Services exist in the {0} database on ", database), database);
                continue;
            }

            foreach (BrokerService service in database.ServiceBroker.Services)
            {
                if (Interrupted)
                    return;
                // The source checks boundness, so an explicitly false switch still excluded system
                // services; the switch value decides here, so an explicit false behaves like absent.
                if (ExcludeSystemService.IsPresent && service.IsSystemObject)
                    continue;

                PSObject output = PSObject.AsPSObject(service);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database", "ServiceID" })
                    output.Properties.Remove(name);
                OutputHelper.AddInstanceProperties(output, database.Parent);
                output.Properties.Add(new PSNoteProperty("Database", database.Name));
                OutputHelper.AddAliasProperty(output, "ServiceID", "ID");
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "InstanceName", "SqlInstance", "Database", "Owner",
                    "ServiceID", "Name", "QueueSchema", "QueueName");
                WriteObject(output);
            }
        }
    }
}
