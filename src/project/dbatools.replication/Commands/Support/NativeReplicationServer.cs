#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Replication;

namespace Dataplat.Dbatools.Commands;

/// <summary>The native connection and decorated output shared by replication commands.</summary>
internal static class NativeReplicationServer
{
    internal static Server Connect(DbaInstanceParameter instance, PSCredential? credential, bool azureUnsupported = false)
    {
        SmoConnectionRequest request = new();
        request.Instance = instance;
        request.SqlCredential = credential;
        request.AzureUnsupported = azureUnsupported;
        return ConnectionService.GetServer(request);
    }

    internal static PSObject Wrap(Server server)
    {
        ReplicationServer replicationServer = new();
        replicationServer.ConnectionContext = server.ConnectionContext;
        PSObject wrapped = PSObject.AsPSObject(replicationServer);
        ReplaceNoteProperty(wrapped, "ComputerName", SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", SmoServerExtensions.GetDomainInstanceName(server));
        OutputHelper.SetDefaultDisplayPropertySet(wrapped, "ComputerName", "InstanceName", "SqlInstance", "IsDistributor", "IsPublisher", "DistributionServer", "DistributionDatabase");
        return wrapped;
    }

    /// <summary>
    /// The record a pinned catch receives as $_ when its Connect-DbaInstance fails. Connect-DbaInstance forces its own
    /// EnableException on, so a connection failure or refusal is its Stop-Function throw: the warning is logged without display
    /// and the thrown record lands in $error. caughtNestedStopFunction is the calling cmdlet's CaughtNestedStopFunction.
    /// Returns null for a failure that did not come from the connection itself.
    /// </summary>
    internal static ErrorRecord? NestedConnectFailure(DbaInstanceParameter instance, Exception failure,
        Func<string, string, object, ErrorRecord, ErrorCategory, bool, ErrorRecord> caughtNestedStopFunction)
    {
        if (failure is not ConnectionResolutionException resolution)
            return null;

        if (resolution.Kind == ConnectionResolutionFailure.ConnectFailure)
        {
            // PS: Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
            ErrorRecord connectionError = new(resolution.InnerException ?? resolution, "dbatools_Connect-DbaInstance", ErrorCategory.NotSpecified, instance);
            return caughtNestedStopFunction("Connect-DbaInstance", "Failure", instance, connectionError, ErrorCategory.ConnectionError, false);
        }

        // PS: Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue, and the other refusals
        return caughtNestedStopFunction("Connect-DbaInstance", resolution.Message, instance, null!, ErrorCategory.NotSpecified, false);
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        PSPropertyInfo? existing = wrapped.Properties[name];
        if (existing is PSNoteProperty)
            wrapped.Properties.Remove(name);
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }
}
