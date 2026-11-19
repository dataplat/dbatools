#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves Resource Governor configuration and status from SQL Server instances</summary>
[Cmdlet(VerbsCommon.Get, "DbaResourceGovernor")]
public sealed class GetDbaResourceGovernorCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
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
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;

            // Azure SQL Database has no user-configurable Resource Governor (SQL Server and Managed Instance only), so the command
            // refuses it as Connect-DbaInstance -AzureUnsupported does: correction azure-unsupported.
            Server? server = ConnectInstance(instance, minimumVersion: 10, azureUnsupported: true);
            if (server is null)
                continue;

            // As the pin: no governor object, no output (its Select-DefaultView returns nothing for $null).
            ResourceGovernor? governor = server.ResourceGovernor;
            if (governor is null)
                continue;

            PSObject output = PSObject.AsPSObject(governor);
            // SMO can reuse the governor object; preserve Add-Member -Force on repeated calls.
            foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
                output.Properties.Remove(name);
            OutputHelper.AddInstanceProperties(output, server);
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "InstanceName", "SqlInstance", "ClassifierFunction", "Enabled",
                "MaxOutstandingIOPerVolume", "ReconfigurePending", "ResourcePools", "ExternalResourcePools");
            WriteObject(output);
        }
    }
}
