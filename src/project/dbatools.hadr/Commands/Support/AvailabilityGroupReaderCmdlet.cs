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
/// Shared native base of the commands whose pinned function calls Get-DbaAvailabilityGroup
/// -SqlInstance -SqlCredential -AvailabilityGroup without -EnableException: the nested call's
/// connect, HADR check, group filter and group decoration run here, and its Stop-Function
/// warnings keep its name and never throw, unless a command forwards -EnableException as its pinned call does,
/// or its pinned call adds -EnableException inside its own try/catch.
/// </summary>
public abstract class AvailabilityGroupReaderCmdlet : DbaBaseCmdlet
{
    private const string AvailabilityGroupCommandName = "Get-DbaAvailabilityGroup";

    // PS: Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
    // azureUnsupported: a command's own recorded correction refuses Azure SQL Database at this
    // connect, as Connect-DbaInstance -AzureUnsupported does; each command opts in for itself.
    // forwardEnableException: for a pinned call that adds -EnableException:$EnableException, the nested
    // Stop-Function keeps the caller's switch, so under -EnableException it throws instead of warning.
    // nestedEnableException: for a pinned call that adds -EnableException inside a try whose catch
    // reports the failure itself, the first nested Stop-Function logs without display and throws
    // AvailabilityGroupLookupException, ending the lookup; the caller catches it as the pin's catch does.
    // wildcardNames: a command's own recorded correction for help that documents -AvailabilityGroup
    // wildcards the -in filter never honours (WildcardNameFilter rule E+, over the instance's groups).
    // nestedConnectRecord: a failed connect first gives what the absorbed Connect-DbaInstance's own Stop-Function
    // gives in the pin (its EnableException is always on): its warning, and its record in $Error and the caller's
    // -ErrorVariable, ahead of the nested Get-DbaAvailabilityGroup's Stop-Function; see WriteNestedConnectRecord.
    protected List<AvailabilityGroup> GetAvailabilityGroups(DbaInstanceParameter[] instances, PSCredential? credential, string[]? names, bool azureUnsupported = false, bool forwardEnableException = false, bool nestedEnableException = false, bool wildcardNames = false, bool nestedConnectRecord = false)
    {
        List<AvailabilityGroup> groups = new List<AvailabilityGroup>();
        ReadAvailabilityGroups(instances, credential, names, (ag, wrapped) => groups.Add(ag),
            azureUnsupported, forwardEnableException, nestedEnableException, wildcardNames, nestedConnectRecord: nestedConnectRecord);
        return groups;
    }

    // The lookup itself: each decorated group goes to onGroup as soon as it is read, so a caller that
    // writes it at once keeps an earlier instance's output when a later instance's Stop-Function throws,
    // as Get-DbaAvailabilityGroup's own process block does. Same opt-ins as GetAvailabilityGroups.
    // isPrimary: the -IsPrimary decoration (IsPrimary note, its own default display set).
    protected void ReadAvailabilityGroups(DbaInstanceParameter[] instances, PSCredential? credential, string[]? names, Action<AvailabilityGroup, PSObject> onGroup, bool azureUnsupported = false, bool forwardEnableException = false, bool nestedEnableException = false, bool wildcardNames = false, bool isPrimary = false, bool nestedConnectRecord = false)
    {
        foreach (DbaInstanceParameter instance in instances)
        {
            Server server;
            try
            {
                WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
                SmoConnectionRequest request = new SmoConnectionRequest
                {
                    Instance = instance,
                    SqlCredential = credential,
                    MinimumVersion = 11,
                    AzureUnsupported = azureUnsupported,
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
            catch (Exception ex)
            {
                ErrorRecord record = new ErrorRecord(ex, "dbatools_" + AvailabilityGroupCommandName, ErrorCategory.ConnectionError, instance);
                if (nestedConnectRecord)
                {
                    WriteNestedConnectRecord(instance, ex);
                }
                StopAvailabilityGroupLookup("Failure", instance, record, ErrorCategory.ConnectionError, forwardEnableException, nestedEnableException);
                continue;
            }

            if (!server.IsHadrEnabled)
            {
                StopAvailabilityGroupLookup(string.Format("Availability Group (HADR) is not configured for the instance: {0}.", instance), instance, null, ErrorCategory.NotSpecified, forwardEnableException, nestedEnableException);
                continue;
            }

            bool filtered = LanguagePrimitives.IsTrue(names);
            WildcardNameMatcher? matcher = null;
            if (filtered && wildcardNames)
            {
                List<string> scope = new List<string>();
                foreach (AvailabilityGroup candidate in server.AvailabilityGroups)
                {
                    scope.Add(candidate.Name);
                }
                matcher = WildcardNameFilter.CreateMatcher(names!, true, (value, name) => LanguagePrimitives.Equals(value, name, true), scope);
            }
            foreach (AvailabilityGroup ag in server.AvailabilityGroups)
            {
                // PS: Where-Object Name -in $AvailabilityGroup
                if (filtered && !(matcher is null ? ContainsName(names!, ag.Name) : matcher.Matches(ag.Name)))
                {
                    continue;
                }

                // Refresh list of databases to fix #9094
                ag.AvailabilityDatabases.Refresh();

                // PS: Add-Member -Force ComputerName, InstanceName, SqlInstance; Select-DefaultView
                PSObject wrapped = PSObject.AsPSObject(ag);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
                {
                    wrapped.Properties.Remove(name);
                }
                OutputHelper.AddInstanceProperties(wrapped, server);
                if (isPrimary)
                {
                    // PS: Add-Member -Force IsPrimary ($ag.LocalReplicaRole -eq "Primary"); 'Name as AvailabilityGroup'
                    wrapped.Properties.Remove("IsPrimary");
                    wrapped.Properties.Add(new PSNoteProperty("IsPrimary", ag.LocalReplicaRole == AvailabilityReplicaRole.Primary));
                    if (wrapped.Properties["AvailabilityGroup"] is null)
                    {
                        OutputHelper.AddAliasProperty(wrapped, "AvailabilityGroup", "Name");
                    }
                    OutputHelper.SetDefaultDisplayPropertySet(wrapped,
                        "ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "IsPrimary");
                }
                else
                {
                    // PS: 'Name as AvailabilityGroup', 'PrimaryReplicaServerName as PrimaryReplica'
                    if (wrapped.Properties["AvailabilityGroup"] is null)
                    {
                        OutputHelper.AddAliasProperty(wrapped, "AvailabilityGroup", "Name");
                    }
                    if (wrapped.Properties["PrimaryReplica"] is null)
                    {
                        OutputHelper.AddAliasProperty(wrapped, "PrimaryReplica", "PrimaryReplicaServerName");
                    }
                    OutputHelper.SetDefaultDisplayPropertySet(wrapped,
                        "ComputerName", "InstanceName", "SqlInstance", "LocalReplicaRole", "AvailabilityGroup",
                        "PrimaryReplica", "ClusterType", "DtcSupportEnabled", "AutomatedBackupPreference",
                        "AvailabilityReplicas", "AvailabilityDatabases", "AvailabilityGroupListeners");
                }
                onGroup(ag, wrapped);
            }
        }
    }

    // PS: -in / -notin compare case-insensitively.
    protected static bool ContainsName(string[] values, string? name)
    {
        foreach (string value in values)
        {
            if (LanguagePrimitives.Equals(value, name, true))
            {
                return true;
            }
        }
        return false;
    }

    /// <summary>
    /// The record a nested Get-DbaAvailabilityGroup -EnableException throws, for the caller's catch ($_).
    /// </summary>
    protected sealed class AvailabilityGroupLookupException : Exception
    {
        /// <summary>Carries the nested Stop-Function's thrown record.</summary>
        /// <param name="errorRecord">The record</param>
        public AvailabilityGroupLookupException(ErrorRecord errorRecord)
            : base(errorRecord.Exception.Message, errorRecord.Exception)
        {
            ErrorRecord = errorRecord;
        }

        /// <summary>The nested Stop-Function's thrown record.</summary>
        public ErrorRecord ErrorRecord { get; }
    }

    // PS (Connect-DbaInstance, inside the nested Get-DbaAvailabilityGroup's try): Connect-DbaInstance forces its own
    // EnableException on, so its Stop-Function -Continue throws into that catch. Its warning ("[Connect-DbaInstance]
    // Failure | Error connecting to [<instance>]: <cause>", or a refusal's own message) is logged without display and its
    // thrown record lands in $Error and the caller's -ErrorVariable; the nested Stop-Function's own record follows it.
    private void WriteNestedConnectRecord(DbaInstanceParameter instance, Exception failure)
    {
        if (failure is not ConnectionResolutionException resolution)
        {
            return;
        }
        if (resolution.Kind == ConnectionResolutionFailure.ConnectFailure)
        {
            // PS: Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
            ErrorRecord connectionError = new ErrorRecord(resolution.InnerException ?? resolution, "dbatools_Connect-DbaInstance", ErrorCategory.NotSpecified, instance);
            CaughtNestedStopFunction("Connect-DbaInstance", "Failure", target: instance, errorRecord: connectionError, category: ErrorCategory.ConnectionError);
            return;
        }

        // PS: Stop-Function -Target $instance -Message "Azure SQL Database not supported" -Continue, and the other refusals
        CaughtNestedStopFunction("Connect-DbaInstance", resolution.Message, target: instance);
    }

    // Stop-Function -Continue inside the nested Get-DbaAvailabilityGroup, which the pin calls
    // without -EnableException: a warning under that command's name, the record in $error, no throw.
    // With forwardEnableException the caller's switch stays, as -EnableException:$EnableException passes it on.
    // With nestedEnableException the nested Stop-Function throws for the caller's catch instead, ending the lookup.
    private void StopAvailabilityGroupLookup(string message, object target, ErrorRecord? errorRecord, ErrorCategory category, bool forwardEnableException, bool nestedEnableException)
    {
        if (nestedEnableException)
        {
            throw new AvailabilityGroupLookupException(CaughtNestedStopFunction(AvailabilityGroupCommandName, message,
                target: target, errorRecord: errorRecord, category: category));
        }

        SwitchParameter callerSetting = EnableException;
        EnableException = forwardEnableException ? callerSetting : new SwitchParameter(false);
        try
        {
            StopAttributedFunction(AvailabilityGroupCommandName, message, target: target, errorRecord: errorRecord, category: category,
                continueLoop: true, interruptCallerScope: false);
        }
        finally
        {
            EnableException = callerSetting;
        }
    }
}
