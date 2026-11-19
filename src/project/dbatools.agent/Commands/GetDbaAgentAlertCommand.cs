#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using AgentAlert = Microsoft.SqlServer.Management.Smo.Agent.Alert;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves SQL Server Agent alert configurations from one or more instances</summary>
[Cmdlet(VerbsCommon.Get, "DbaAgentAlert")]
[OutputType(typeof(AgentAlert))]
public sealed class GetDbaAgentAlertCommand : DbaInstanceCmdlet
{
    /// <summary>Target SQL Server instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Alert-name patterns to include, preserving repeated matches.</summary>
    [Parameter(Position = 2)]
    public string[]? Alert { get; set; }

    /// <summary>Alert-name patterns to exclude.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeAlert { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;
            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;

            WriteMessage(MessageLevel.Debug, String.Format("Getting Edition from {0}", server));
            WriteMessage(MessageLevel.Debug, String.Format("{0} is a {1}", server, server.Edition));
            if (server.Edition.StartsWith("Express", StringComparison.OrdinalIgnoreCase))
            {
                StopFunction(String.Format("There is no SQL Agent on {0}, it's a {1}", server, server.Edition), continueLoop: true);
                continue;
            }

            List<AgentAlert> selected = new();
            if (TestBound(nameof(Alert)))
            {
                foreach (string pattern in Alert ?? Array.Empty<string>())
                {
                    WildcardPattern filter = new(pattern ?? String.Empty, WildcardOptions.IgnoreCase);
                    foreach (AgentAlert item in server.JobServer.Alerts)
                    {
                        if (filter.IsMatch(item.Name))
                            selected.Add(item);
                    }
                }
            }
            else
            {
                foreach (AgentAlert item in server.JobServer.Alerts)
                    selected.Add(item);
            }

            if (TestBound(nameof(ExcludeAlert)))
            {
                foreach (string pattern in ExcludeAlert ?? Array.Empty<string>())
                {
                    WildcardPattern filter = new(pattern ?? String.Empty, WildcardOptions.IgnoreCase);
                    selected.RemoveAll(item => filter.IsMatch(item.Name));
                }
            }

            foreach (AgentAlert item in selected)
            {
                DbaDateTime lastRaised = new(item.LastOccurrenceDate);
                PSObject output = PSObject.AsPSObject(item);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "Notifications", "LastRaised" })
                    output.Properties.Remove(name);
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("Notifications", item.EnumNotifications()));
                output.Properties.Add(new PSNoteProperty("LastRaised", lastRaised));
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "SqlInstance", "InstanceName", "Name", "ID", "JobName", "AlertType", "CategoryName",
                    "Severity", "MessageId", "IsEnabled", "DelayBetweenResponses", "LastRaised", "OccurrenceCount");
                WriteObject(output);
            }
        }
    }
}
