#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Smo.Mail;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The nested Get-DbaDbMail read of named instances, shared by the native Database Mail readers. A base class rather than
/// a static helper, because the read writes through DbaBaseCmdlet's protected message and stop members.
/// </summary>
public abstract class DbMailCmdlet : DbaBaseCmdlet
{
    // PS: $InputObject += Get-DbaDbMail -SqlInstance $SqlInstance -SqlCredential $SqlCredential. -EnableException never
    // reaches that call, so its Stop-Function warns under its own name. All instances are read before the first server leaves.
    /// <summary>Adds the mail object of each named instance, or reports the binder fault of an array holding a null.</summary>
    protected void AddNamedInstances(DbaInstanceParameter[] sqlInstance, PSCredential? sqlCredential, List<SqlMail?> mailServers,
        Action reportNestedBindingFault)
    {
        if (Array.Exists(sqlInstance, instance => instance is null))
        {
            reportNestedBindingFault();
            return;
        }

        foreach (DbaInstanceParameter instance in sqlInstance)
        {
            SqlMail? mail = ReadMail(instance, sqlCredential);
            if (mail is not null)
                mailServers.Add(mail);
        }
    }

    /// <summary>The nested Get-DbaDbMail read of one instance; null after its warning.</summary>
    protected SqlMail? ReadMail(DbaInstanceParameter instance, PSCredential? sqlCredential)
    {
        Server server;
        try
        {
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
            server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance,
                SqlCredential = sqlCredential,
                // Correction azure-database-mail-refusal: the gate the converted Get-DbaDbMail carries.
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            });
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_Get-DbaDbMail", ErrorCategory.ConnectionError, instance);
            WarnNestedStopFunction("Get-DbaDbMail", "Failure", instance, record, ErrorCategory.ConnectionError);
            return null;
        }
        SetActiveConnection(server.ConnectionContext);

        try
        {
            SqlMail mail = server.Mail;
            PSObject output = PSObject.AsPSObject(mail);
            RemoveProperties(output, "ComputerName", "InstanceName", "SqlInstance");
            OutputHelper.AddInstanceProperties(output, server);
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "InstanceName", "SqlInstance", "Profiles", "Accounts", "ConfigurationValues", "Properties");
            return mail;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_Get-DbaDbMail", ErrorCategory.NotSpecified, null);
            WarnNestedStopFunction("Get-DbaDbMail", "Failure", null, record);
            return null;
        }
    }

    // PS: Add-Member -Force replaces a note an earlier call left on the same object.
    /// <summary>Removes the named notes before they are added again.</summary>
    protected static void RemoveProperties(PSObject output, params string[] names)
    {
        foreach (string name in names)
            output.Properties.Remove(name);
    }
}
