#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Mail;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves Database Mail configuration including profiles, accounts, and settings from SQL Server instances</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbMail")]
[OutputType(typeof(SqlMail))]
public sealed class GetDbaDbMailCommand : DbaInstanceCmdlet
{
    /// <summary>
    /// The target SQL Server instance or instances.
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

            try
            {
                PSObject output = PSObject.AsPSObject(server.Mail);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
                    output.Properties.Remove(name);
                OutputHelper.AddInstanceProperties(output, server);
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "InstanceName", "SqlInstance", "Profiles", "Accounts", "ConfigurationValues", "Properties");
                WriteObject(output);
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                ErrorRecord record = new(ex, MyInvocation.MyCommand.Name, ErrorCategory.NotSpecified, null);
                StopFunction("Failure", errorRecord: record, continueLoop: true);
            }
        }
    }
}
