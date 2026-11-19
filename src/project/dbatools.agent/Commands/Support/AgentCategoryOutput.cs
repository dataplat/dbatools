#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;
using AgentJob = Microsoft.SqlServer.Management.Smo.Agent.Job;

namespace Dataplat.Dbatools.Commands;

internal static class AgentCategoryOutput
{
    internal static int CountUsage(Server server, AlertCategory category)
    {
        int count = 0;
        foreach (Alert alert in server.JobServer.Alerts)
        {
            if (String.Equals(alert.CategoryName, category.Name, StringComparison.InvariantCultureIgnoreCase))
                count++;
        }
        return count;
    }

    internal static int CountUsage(Server server, JobCategory category)
    {
        int count = 0;
        foreach (AgentJob job in server.JobServer.Jobs)
        {
            if (job.CategoryID == category.ID)
                count++;
        }
        return count;
    }

    internal static void DecorateAlert(PSObject output, Server server, int count)
    {
        Decorate(output, server, count, "AlertCount",
            "ComputerName", "InstanceName", "SqlInstance", "Name", "ID", "AlertCount");
    }

    internal static void DecorateJob(PSObject output, Server server, int count)
    {
        Decorate(output, server, count, "JobCount",
            "ComputerName", "InstanceName", "SqlInstance", "Name", "ID", "CategoryType", "JobCount");
    }

    private static void Decorate(PSObject output, Server server, int count, string countProperty, params string[] displayProperties)
    {
        // SMO may return an object decorated by an earlier invocation.
        foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", countProperty })
            output.Properties.Remove(property);
        OutputHelper.AddInstanceProperties(output, server);
        output.Properties.Add(new PSNoteProperty(countProperty, count));
        OutputHelper.SetDefaultDisplayPropertySet(output, displayProperties);
    }
}
