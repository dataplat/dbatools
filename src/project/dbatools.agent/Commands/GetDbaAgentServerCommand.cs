#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Agent;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves SQL Server Agent service configuration and status information</summary>
[Cmdlet(VerbsCommon.Get, "DbaAgentServer")]
[OutputType(typeof(JobServer))]
public sealed class GetDbaAgentServerCommand : DbaInstanceCmdlet
{
    /// <summary>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    ///
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    ///
    /// For MFA support, please use Connect-DbaInstance.
    /// </summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            PSObject output = PSObject.AsPSObject(server.JobServer);
            foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance", "JobHistoryIsEnabled" })
                output.Properties.Remove(name);
            OutputHelper.AddInstanceProperties(output, server);
            // Keep this property live when callers edit the SMO object in memory.
            output.Properties.Add(new PSCodeProperty("JobHistoryIsEnabled",
                ((Func<PSObject, bool>)GetJobHistoryIsEnabled).Method));
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "InstanceName", "SqlInstance", "AgentDomainGroup", "AgentLogLevel",
                "AgentMailType", "AgentShutdownWaitTime", "ErrorLogFile", "IdleCpuDuration", "IdleCpuPercentage",
                "IsCpuPollingEnabled", "JobServerType", "LoginTimeout", "JobHistoryIsEnabled", "MaximumHistoryRows",
                "MaximumJobHistoryRows", "MsxAccountCredentialName", "MsxAccountName", "MsxServerName", "Name",
                "NetSendRecipient", "ServiceAccount", "ServiceStartMode", "SqlAgentAutoStart", "SqlAgentMailProfile",
                "SqlAgentRestart", "SqlServerRestart", "State", "SysAdminOnly");
            WriteObject(output);
        }
    }

    /// <summary>Native getter for the calculated job-history flag.</summary>
    public static bool GetJobHistoryIsEnabled(PSObject value)
    {
        return ((JobServer)value.BaseObject).MaximumHistoryRows != -1;
    }
}
