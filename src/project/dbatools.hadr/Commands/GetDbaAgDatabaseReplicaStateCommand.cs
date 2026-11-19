#nullable enable

using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaAgDatabaseReplicaState.ps1 at refs/pins/dbatools-2026-10-22. The nested
// Get-DbaAvailabilityGroup call runs through AvailabilityGroupReaderCmdlet; the replica and
// database walk and the 40-property output object run here.
/// <summary>Retrieves the runtime state of databases participating in availability groups across all replicas.</summary>
/// <para>
/// Retrieves comprehensive health monitoring information about databases participating in SQL Server availability groups, similar to the SSMS AG Dashboard. This function returns detailed database replica state information for all replicas in the availability group.
/// </para>
/// <para>
/// The class Microsoft.SqlServer.Management.Smo.DatabaseReplicaState represents the runtime state of a database that's participating in an availability group. This database may be located on any of the replicas that compose the availability group.
/// </para>
/// <para>
/// Use this command to monitor availability group health, troubleshoot synchronization issues, verify failover readiness, identify data loss risks, and generate detailed operational reports showing the state of each database on each replica in your availability groups.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgDatabaseReplicaState -SqlInstance sql2017a
/// </code>
/// <para>
/// Returns database replica state information for all databases in all availability groups on sql2017a
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgDatabaseReplicaState -SqlInstance sql2017a -AvailabilityGroup AG101
/// </code>
/// <para>
/// Returns database replica state information for all databases in the availability group AG101 on sql2017a
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAgDatabaseReplicaState -SqlInstance sql2017a -AvailabilityGroup AG101 -Database AppDB
/// </code>
/// <para>
/// Returns database replica state information for the AppDB database in the availability group AG101 on sql2017a
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAvailabilityGroup -SqlInstance sqlcluster -AvailabilityGroup SharePoint | Get-DbaAgDatabaseReplicaState
/// </code>
/// <para>
/// Returns database replica state information for all databases in the availability group SharePoint on server sqlcluster
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaAvailabilityGroup -SqlInstance sqlcluster -AvailabilityGroup SharePoint | Get-DbaAgDatabaseReplicaState -Database Sharepoint_Config
/// </code>
/// <para>
/// Returns database replica state information for the Sharepoint_Config database in the availability group SharePoint on server sqlcluster
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: AG, HA, Monitoring, Health
/// Author: Andreas Jordan (@andreasjordan)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2025 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaAgDatabaseReplicaState" />
[Cmdlet(VerbsCommon.Get, "DbaAgDatabaseReplicaState")]
public sealed class GetDbaAgDatabaseReplicaStateCommand : AvailabilityGroupReaderCmdlet
{
    // Positions follow the pinned function's automatic positional binding: every
    // non-switch parameter in declaration order.

    /// <para>
    /// The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.
    /// </para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies which availability groups to query for database replica state information. Accepts multiple availability group names.
    /// Use this to limit results to specific availability groups when you have multiple AGs on the same instance.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? AvailabilityGroup { get; set; }

    /// <para>
    /// Specifies which availability group databases to return replica state information for. Accepts multiple database names.
    /// Use this to focus on specific databases when troubleshooting AG issues or monitoring particular applications.
    /// </para>
    [Parameter(Position = 3)]
    public string[]? Database { get; set; }

    /// <para>
    /// Accepts availability group objects from Get-DbaAvailabilityGroup via pipeline input.
    /// Use this when you want to chain commands to get database replica state details from already retrieved availability groups.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public AvailabilityGroup[]? InputObject { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        // The pinned process block has no Test-FunctionInterrupt check, so a stop in an earlier
        // record does not end later ones.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // PS: $InputObject += Get-DbaAvailabilityGroup ... - per record, the bound groups first.
        List<AvailabilityGroup> groups = new List<AvailabilityGroup>();
        if (InputObject is not null)
        {
            groups.AddRange(InputObject);
        }
        if (SqlInstance is not null && LanguagePrimitives.IsTrue(SqlInstance))
        {
            // Correction azure-unsupported: Azure SQL Database is refused as Connect-DbaInstance
            // -AzureUnsupported does; availability groups do not exist there.
            groups.AddRange(GetAvailabilityGroups(SqlInstance, SqlCredential, AvailabilityGroup, azureUnsupported: true));
        }

        bool filtered = LanguagePrimitives.IsTrue(Database);
        foreach (AvailabilityGroup? ag in groups)
        {
            if (ag is null)
            {
                continue;
            }
            PSObject agObject = PSObject.AsPSObject(ag);

            foreach (AvailabilityReplica replica in ag.AvailabilityReplicas)
            {
                // PS: $ag.DatabaseReplicaStates | Where-Object AvailabilityReplicaId -eq $replicaId
                List<DatabaseReplicaState> replicaStates = new List<DatabaseReplicaState>();
                foreach (DatabaseReplicaState state in ag.DatabaseReplicaStates)
                {
                    if (state.AvailabilityReplicaId == replica.UniqueId)
                    {
                        replicaStates.Add(state);
                    }
                }

                foreach (AvailabilityDatabase db in ag.AvailabilityDatabases)
                {
                    if (filtered && !ContainsName(Database!, db.Name))
                    {
                        continue;
                    }

                    // AvailabilityDateabaseId is a typo in SMO but we have to use it as-is
                    // See https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.databasereplicastate.availabilitydateabaseid
                    // The collection is keyed on replica server and database name, so at most one state matches.
                    DatabaseReplicaState? databaseReplicaState = null;
                    foreach (DatabaseReplicaState state in replicaStates)
                    {
                        if (state.AvailabilityDateabaseId == db.UniqueId)
                        {
                            databaseReplicaState = state;
                            break;
                        }
                    }
                    if (databaseReplicaState is null)
                    {
                        continue;
                    }

                    WriteObject(NewStateObject(agObject, ag, replica, databaseReplicaState));
                }
            }
        }
    }

    // PS: [PSCustomObject]@{ ... } with the pinned property order. The instance triple and
    // PrimaryReplica are read from the group as PowerShell does: the notes and alias that
    // Get-DbaAvailabilityGroup adds, absent (null) on an undecorated group.
    private static PSObject NewStateObject(PSObject agObject, AvailabilityGroup ag, AvailabilityReplica replica, DatabaseReplicaState state)
    {
        PSObject output = new PSObject();
        output.Properties.Add(new PSNoteProperty("ComputerName", agObject.Properties["ComputerName"]?.Value)); // style-ok: cs-output-props the pin reads $ag.ComputerName from the input group, not a connection
        output.Properties.Add(new PSNoteProperty("InstanceName", agObject.Properties["InstanceName"]?.Value)); // style-ok: cs-output-props the pin reads $ag.InstanceName from the input group, not a connection
        output.Properties.Add(new PSNoteProperty("SqlInstance", agObject.Properties["SqlInstance"]?.Value)); // style-ok: cs-output-props the pin reads $ag.SqlInstance from the input group, not a connection
        AddNote(output, "AvailabilityGroup", ag.Name);
        AddNote(output, "PrimaryReplica", agObject.Properties["PrimaryReplica"]?.Value);
        AddNote(output, "ReplicaServerName", state.AvailabilityReplicaServerName);
        AddNote(output, "ReplicaRole", state.ReplicaRole);
        AddNote(output, "ReplicaAvailabilityMode", replica.AvailabilityMode);
        AddNote(output, "ReplicaFailoverMode", replica.FailoverMode);
        AddNote(output, "ReplicaConnectionState", replica.ConnectionState);
        AddNote(output, "ReplicaJoinState", replica.JoinState);
        AddNote(output, "ReplicaSynchronizationState", replica.RollupSynchronizationState);
        AddNote(output, "DatabaseName", state.AvailabilityDatabaseName);
        AddNote(output, "SynchronizationState", state.SynchronizationState);
        AddNote(output, "IsFailoverReady", state.IsFailoverReady);
        AddNote(output, "IsJoined", state.IsJoined);
        AddNote(output, "IsSuspended", state.IsSuspended);
        AddNote(output, "SuspendReason", state.SuspendReason);
        AddNote(output, "EstimatedRecoveryTime", state.EstimatedRecoveryTime);
        AddNote(output, "EstimatedDataLoss", state.EstimatedDataLoss);
        AddNote(output, "SynchronizationPerformance", state.SynchronizationPerformance);
        AddNote(output, "LogSendQueueSize", state.LogSendQueueSize);
        AddNote(output, "LogSendRate", state.LogSendRate);
        AddNote(output, "RedoQueueSize", state.RedoQueueSize);
        AddNote(output, "RedoRate", state.RedoRate);
        AddNote(output, "FileStreamSendRate", state.FileStreamSendRate);
        AddNote(output, "EndOfLogLSN", state.EndOfLogLSN);
        AddNote(output, "RecoveryLSN", state.RecoveryLSN);
        AddNote(output, "TruncationLSN", state.TruncationLSN);
        AddNote(output, "LastCommitLSN", state.LastCommitLSN);
        AddNote(output, "LastCommitTime", state.LastCommitTime);
        AddNote(output, "LastHardenedLSN", state.LastHardenedLSN);
        AddNote(output, "LastHardenedTime", state.LastHardenedTime);
        AddNote(output, "LastReceivedLSN", state.LastReceivedLSN);
        AddNote(output, "LastReceivedTime", state.LastReceivedTime);
        AddNote(output, "LastRedoneLSN", state.LastRedoneLSN);
        AddNote(output, "LastRedoneTime", state.LastRedoneTime);
        AddNote(output, "LastSentLSN", state.LastSentLSN);
        AddNote(output, "LastSentTime", state.LastSentTime);
        return output;
    }

    private static void AddNote(PSObject output, string name, object? value)
    {
        output.Properties.Add(new PSNoteProperty(name, value));
    }
}
