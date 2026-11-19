#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Shared native base of the commands whose pinned function reads its governors through a nested Get-DbaResourceGovernor
/// -SqlInstance -SqlCredential call without -EnableException (Get-DbaRgResourcePool directly, Get-DbaRgWorkloadGroup through the
/// nested Get-DbaRgResourcePool): the nested connect, the decorated governor and pools, and that command's own warning and
/// record on a failed connection, whatever the calling command's -EnableException.
/// </summary>
public abstract class ResourceGovernorReaderCmdlet : DbaInstanceCmdlet
{
    /// <summary>
    /// The nested Get-DbaResourceGovernor -SqlInstance $instance -SqlCredential $SqlCredential for one instance: Connect-DbaInstance
    /// -MinimumVersion 10, the governor decorated as that command does, or, on a failed connection, that command's
    /// Stop-Function -Continue over the record Connect-DbaInstance threw.
    /// </summary>
    /// <param name="instance">The instance to read</param>
    /// <returns>The decorated governor, or null when the connection failed or the server has none</returns>
    protected ResourceGovernor? GetResourceGovernor(DbaInstanceParameter instance)
    {
        Server server;
        try
        {
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
            SmoConnectionRequest request = new()
            {
                Instance = instance,
                SqlCredential = SqlCredential,
                MinimumVersion = 10,
                // Correction azure-unsupported (Get-DbaResourceGovernor, Get-DbaRgResourcePool, Get-DbaRgWorkloadGroup): Azure SQL
                // Database has no user-configurable Resource Governor (SQL Server and Managed Instance only), so the nested read
                // refuses it as Connect-DbaInstance -AzureUnsupported does.
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            };
            server = ConnectionService.GetServer(request);
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception failure)
        {
            // PS (Get-DbaResourceGovernor): catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            WarnNestedStopFunction("Get-DbaResourceGovernor", "Failure", instance, NestedConnectRecord(instance, failure), ErrorCategory.ConnectionError);
            return null;
        }

        ResourceGovernor? governor = server.ResourceGovernor;
        if (governor is null)
            return null;
        PSObject output = PSObject.AsPSObject(governor);
        // SMO can reuse the governor object; preserve Add-Member -Force on repeated calls.
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
            output.Properties.Remove(name);
        OutputHelper.AddInstanceProperties(output, server);
        OutputHelper.SetDefaultDisplayPropertySet(output,
            "ComputerName", "InstanceName", "SqlInstance", "ClassifierFunction", "Enabled",
            "MaxOutstandingIOPerVolume", "ReconfigurePending", "ResourcePools", "ExternalResourcePools");
        return governor;
    }

    /// <summary>
    /// Get-DbaRgResourcePool's decoration of one pool: $respool | Add-Member -Force ComputerName, InstanceName, SqlInstance from the
    /// governor's notes, then Select-DefaultView.
    /// </summary>
    /// <param name="pool">A ResourcePool or ExternalResourcePool of the governor</param>
    /// <param name="resourcegov">The decorated governor that holds the pool</param>
    /// <returns>The decorated pool</returns>
    protected static PSObject DecoratePool(object pool, ResourceGovernor resourcegov)
    {
        PSObject wrapped = PSObject.AsPSObject(pool);
        ReplaceNoteProperty(wrapped, "ComputerName", SmoServerExtensions.GetPSProperty(resourcegov, "ComputerName"));
        ReplaceNoteProperty(wrapped, "InstanceName", SmoServerExtensions.GetPSProperty(resourcegov, "InstanceName"));
        ReplaceNoteProperty(wrapped, "SqlInstance", SmoServerExtensions.GetPSProperty(resourcegov, "SqlInstance"));

        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Id", "Name", "CapCpuPercentage", "IsSystemObject",
            "MaximumCpuPercentage", "MaximumIopsPerVolume", "MaximumMemoryPercentage", "MinimumCpuPercentage",
            "MinimumIopsPerVolume", "MinimumMemoryPercentage", "WorkloadGroups");
        return wrapped;
    }

    /// <summary>Add-Member -Force -MemberType NoteProperty: an earlier note of that name is replaced.</summary>
    /// <param name="wrapped">The object to decorate</param>
    /// <param name="name">The note's name</param>
    /// <param name="value">The note's value</param>
    protected static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        PSPropertyInfo? existing = wrapped.Properties[name];
        if (existing is PSNoteProperty)
            wrapped.Properties.Remove(name);
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }

    /// <summary>
    /// The $_ the nested catch receives. Connect-DbaInstance forces its own EnableException on, so a failed connection or a
    /// refusal is its Stop-Function throw: logged without display, the thrown record kept in $error.
    /// </summary>
    private ErrorRecord NestedConnectRecord(DbaInstanceParameter instance, Exception failure)
    {
        if (failure is not ConnectionResolutionException resolution)
            return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);

        if (resolution.Kind != ConnectionResolutionFailure.ConnectFailure)
        {
            // PS: Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue, and the other refusals
            return CaughtNestedStopFunction("Connect-DbaInstance", resolution.Message, instance);
        }

        // PS: Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
        ErrorRecord connectionError = new(resolution.InnerException ?? resolution, "dbatools_Connect-DbaInstance", ErrorCategory.NotSpecified, instance);
        return CaughtNestedStopFunction("Connect-DbaInstance", "Failure", instance, connectionError, ErrorCategory.ConnectionError);
    }
}
