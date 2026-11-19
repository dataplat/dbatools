#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;

namespace Dataplat.Dbatools.Commands;

/// <summary>Creates SQL Server Agent alert categories through SMO.</summary>
[Cmdlet(VerbsCommon.New, "DbaAgentAlertCategory", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(AlertCategory))]
public sealed class NewDbaAgentAlertCategoryCommand : DbaInstanceCmdlet
{
    /// <summary>Target SQL Server instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Category names to create.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [ValidateNotNullOrEmpty]
    [PsStringArrayCast]
    public string[] Category { get; set; } = null!;

    /// <summary>Suppress inherited confirmation requests.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

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

            foreach (string name in Category)
            {
                if (Interrupted)
                    return;
                bool exists = false;
                foreach (AlertCategory current in server.JobServer.AlertCategories)
                {
                    if (String.Equals(current.Name, name, StringComparison.InvariantCultureIgnoreCase))
                    {
                        exists = true;
                        break;
                    }
                }
                if (exists)
                {
                    StopFunction(String.Format("Alert category {0} already exists on {1}", name, instance),
                        target: instance, continueLoop: true);
                    continue;
                }

                if (ConfirmCategoryChange(instance, name) && !TryCreateCategory(server, instance, name))
                    continue;
                WriteCategory(server, name);
            }
        }
    }

    private bool TryCreateCategory(Server server, DbaInstanceParameter instance, string name)
    {
        bool constructing = true;
        try
        {
            AlertCategory created = new(server.JobServer, name);
            constructing = false;
            created.Create();
            server.JobServer.Refresh();
            return true;
        }
        catch (Exception exception) when (exception is not PipelineStoppedException)
        {
            string message = constructing && exception.Message.IndexOf("newParent", StringComparison.OrdinalIgnoreCase) >= 0
                ? "Cannot create agent alert category through a contained availability group listener. SQL Server Agent objects are instance-level and must be managed on the instance directly. Please connect to the primary replica instead of the listener. Use Get-DbaAvailabilityGroup to find the current primary replica."
                : String.Format("Something went wrong creating the alert category {0} on {1}", name, instance);
            ErrorRecord record = new(exception, "dbatools_New-DbaAgentAlertCategory", ErrorCategory.NotSpecified, name);
            StopFunction(message, target: name, errorRecord: record, continueLoop: true);
            return false;
        }
    }

    private bool ConfirmCategoryChange(DbaInstanceParameter instance, string name)
    {
        string action = String.Format("Adding the alert category {0}", name);
        if (!Force)
            return ShouldProcess(instance.ToString(), action);

        return AgentConfirmation.WithConfirmationSuppressed(
            SessionState, () => ShouldProcess(instance.ToString(), action));
    }

    private void WriteCategory(Server server, string name)
    {
        foreach (AlertCategory category in server.JobServer.AlertCategories)
        {
            if (!String.Equals(category.Name, name, StringComparison.InvariantCultureIgnoreCase))
                continue;
            int count = AgentCategoryOutput.CountUsage(server, category);
            PSObject output = PSObject.AsPSObject(category);
            AgentCategoryOutput.DecorateAlert(output, server, count);
            WriteObject(output);
        }
    }
}
