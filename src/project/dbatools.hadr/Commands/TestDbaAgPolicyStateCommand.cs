#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests the health of an availability group against SQL Server AlwaysOn policy facets.
/// Port of public/Test-DbaAgPolicyState.ps1; surface pinned by
/// migration/baselines/Test-DbaAgPolicyState.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaAgPolicyState")]
public sealed class TestDbaAgPolicyStateCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group or groups to test.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>The secondary replica instance(s). Declared on the source surface; the body does not reference it.</summary>
    [Parameter(Position = 3)]
    public DbaInstanceParameter[]? Secondary { get; set; }

    /// <summary>Alternative credentials for the secondary replica(s). Declared on the source surface; the body does not reference it.</summary>
    [Parameter(Position = 4)]
    public PSCredential? SecondarySqlCredential { get; set; }

    /// <summary>Availability group objects piped from Get-DbaAvailabilityGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop, and the SIMPLEST kind in this family: [CmdletBinding()] with NO
        // ShouldProcess (verified 0 occurrences in the source), so there is NO W3-082 prompt-state
        // transplant, NO gate, and NO state sentinel - the hop is a pure InputObject -> emitted
        // objects transform.
        //
        // NO PARAMETER CARRY, NO cross-record state. The only process-block parameter mutation is
        // `$InputObject +=` at :104, targeting the ValueFromPipeline parameter, which the binder
        // RE-BINDS every record. Both detectors clean; the body's $ag/$server/$replica/
        // $databaseReplicaState are all foreach-locals assigned before every read.
        //
        // TWO carried bound flags for the single guard at :98 (positional multi-name -Not over
        // SqlInstance and InputObject, meaning NEITHER bound) -> -not ($__boundSqlInstance -or
        // $__boundInputObject). Secondary and SecondarySqlCredential are on the surface (source
        // positions 3/4) but the body never references them, so they are not passed into the hop.
        // $EnableException IS passed even though the body never textually uses it, because
        // Stop-Function scope-walks the caller's $EnableException at the guard.
        //
        // T8/DEF-002 EXPOSURE (shared-runtime, blocked on A, escalated): AvailabilityGroup is
        // [string[]] and its value flows to Get-DbaAvailabilityGroup at :104, so `-AvailabilityGroup
        // @($null)` would diverge (<null> compiled vs <''> function) until hadr gains PsCompat and
        // this parameter gets [PsStringArrayCast]. Read-only Test-* so the DEF-001 buffered-output
        // class is far weaker here (codex precision: not "no terminating throw" categorically - a
        // later $ag.Refresh()/SMO member CAN throw under -ErrorAction Stop after earlier emits - but
        // there is no explicit post-emit throw or non-continue Stop-Function path, and a read-only
        // command can only lose partial report output, never conceal a completed mutation, so the
        // established read-only accept-and-link disposition applies).
        // DEF-001 closed via InvokeScopedStreaming (ab7492c); read-only so no WhatIf interaction.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, AvailabilityGroup, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 98-535 (extracted programmatically, not hand-transcribed) after stripping one
    // -FunctionName append and reversing the single Test-Bound rewrite (the guard at :98). All of
    // the source's explanatory block comments (the WSFC/facet documentation) ride untouched. There
    // is no gate and no sentinel; the dot-block preserves the guard's early return at :100.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$AvailabilityGroup, [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Test-DbaAgPolicyState
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($ag in $InputObject) {
            $server = $ag.Parent
            $ag.Refresh()

            <#
            WSFC cluster service is offline
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/wsfc-cluster-service-is-offline
            Policy Name: WSFC Cluster State
            Issue: WSFC cluster service is offline.
            Category: Critical
            Facet: Instance of SQL Server

            Name           : AlwaysOnAgWSFClusterHealthCondition
            Facet          : Server
            ExpressionNode : @ClusterQuorumState = Enum('Microsoft.SqlServer.Management.Smo.ClusterQuorumState', 'NormalQuorum')
            #>

            $isHealthy = $server.ClusterQuorumState -eq "NormalQuorum"
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                Replica           = $null
                Database          = $null
                PolicyName        = "WSFC Cluster State"
                Category          = "Critical"
                Facet             = "Instance of SQL Server"
                IsHealthy         = $isHealthy
                Issue             = if ($isHealthy) { $null } else { "WSFC cluster service is offline." }
                Details           = "ClusterQuorumState is $($server.ClusterQuorumState)"
            }

            $agState = New-Object -TypeName "Microsoft.SqlServer.Management.Smo.AvailabilityGroupState" -ArgumentList $ag

            <#
            Always On Availability group is offline
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-group-is-offline
            Policy Name: Availability Group Online State
            Issue: Availability group is offline.
            Category: Critical
            Facet: Availability group

            Name           : AlwaysOnAgOnlineStateHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : @IsOnline = True()
            #>

            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                Replica           = $null
                Database          = $null
                PolicyName        = "Availability Group Online State"
                Category          = "Critical"
                Facet             = "Availability group"
                IsHealthy         = $agState.IsOnline
                Issue             = if ($agState.IsOnline) { $null } else { "Availability group is offline." }
                Details           = "IsOnline is $($agState.IsOnline)"
            }

            <#
            Always On availability group is not ready for automatic failover
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-group-is-not-ready-for-automatic-failover
            Policy Name: Availability Group Automatic Failover Readiness
            Issue: Availability group is not ready for automatic failover.
            Category: Critical
            Facet: Availability group

            Name           : AlwaysOnAgAutomaticFailoverHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : (@IsAutoFailover = True() AND @NumberOfSynchronizedSecondaryReplicas > 0) OR @IsAutoFailover = False()
            #>

            $isHealthy = (-not $agState.IsAutoFailover) -or ($agState.NumberOfSynchronizedSecondaryReplicas -gt 0)
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                Replica           = $null
                Database          = $null
                PolicyName        = "Availability Group Automatic Failover Readiness"
                Category          = "Critical"
                Facet             = "Availability group"
                IsHealthy         = $isHealthy
                Issue             = if ($isHealthy) { $null } else { "Availability group is not ready for automatic failover." }
                Details           = "IsAutoFailover is $($agState.IsAutoFailover), NumberOfSynchronizedSecondaryReplicas is $($agState.NumberOfSynchronizedSecondaryReplicas)"
            }

            <#
            Some availability replicas are disconnected
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/some-availability-replicas-are-disconnected
            Policy Name: Availability Replicas Connection State
            Issue: Some availability replicas are disconnected.
            Category: Warning
            Facet: Availability group

            Name           : AlwaysOnAgReplicasConnectionHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : @NumberOfDisconnectedReplicas = 0
            #>

            $isHealthy = $agState.NumberOfDisconnectedReplicas -eq 0
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                Replica           = $null
                Database          = $null
                PolicyName        = "Availability Replicas Connection State"
                Category          = "Warning"
                Facet             = "Availability group"
                IsHealthy         = $isHealthy
                Issue             = if ($isHealthy) { $null } else { "Some availability replicas are disconnected." }
                Details           = "NumberOfDisconnectedReplicas is $($agState.NumberOfDisconnectedReplicas)"
            }

            <#
            Some availability replicas are not synchronizing data
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/some-availability-replicas-are-not-synchronizing-data
            Policy Name: Availability Replicas Data Synchronization State
            Issue: Some availability replicas are not synchronizing data.
            Category: Warning
            Facet: Availability group

            Name           : AlwaysOnAgReplicasDataSynchronizationHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : @NumberOfNotSynchronizingReplicas = 0
            #>

            $isHealthy = $agState.NumberOfNotSynchronizingReplicas -eq 0
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                Replica           = $null
                Database          = $null
                PolicyName        = "Availability Replicas Data Synchronization State"
                Category          = "Warning"
                Facet             = "Availability group"
                IsHealthy         = $isHealthy
                Issue             = if ($isHealthy) { $null } else { "Some availability replicas are not synchronizing data." }
                Details           = "NumberOfNotSynchronizingReplicas is $($agState.NumberOfNotSynchronizingReplicas)"
            }

            <#
            Some availability replicas do not have a healthy role
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/some-availability-replicas-do-not-have-a-healthy-role
            Policy Name: Availability Replicas Role State
            Issue: Some availability replicas do not have a healthy role.
            Category: Warning
            Facet: Availability group

            Name           : AlwaysOnAgReplicasRoleHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : @NumberOfReplicasWithUnhealthyRole = 0
            #>

            $isHealthy = $agState.NumberOfReplicasWithUnhealthyRole -eq 0
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                Replica           = $null
                Database          = $null
                PolicyName        = "Availability Replicas Role State"
                Category          = "Warning"
                Facet             = "Availability group"
                IsHealthy         = $isHealthy
                Issue             = if ($isHealthy) { $null } else { "Some availability replicas do not have a healthy role." }
                Details           = "NumberOfReplicasWithUnhealthyRole is $($agState.NumberOfReplicasWithUnhealthyRole)"
            }

            <#
            Some synchronous replicas are not synchronized
            Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/some-synchronous-replicas-are-not-synchronized
            Policy Name: Synchronous Replicas Data Synchronization State
            Issue: Some synchronous replicas are not synchronized.
            Category: Warning
            Facet: Availability group

            Name           : AlwaysOnAgSynchronousReplicasDataSynchronizationHealthCondition
            Facet          : IAvailabilityGroupState
            ExpressionNode : @NumberOfNotSynchronizedReplicas = 0
            #>

            $isHealthy = $agState.NumberOfNotSynchronizedReplicas -eq 0
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.Name
                Replica           = $null
                Database          = $null
                PolicyName        = "Synchronous Replicas Data Synchronization State"
                Category          = "Warning"
                Facet             = "Availability group"
                IsHealthy         = $isHealthy
                Issue             = if ($isHealthy) { $null } else { "Some synchronous replicas are not synchronized." }
                Details           = "NumberOfNotSynchronizedReplicas is $($agState.NumberOfNotSynchronizedReplicas)"
            }

            foreach ($replica in $ag.AvailabilityReplicas) {
                <#
                Availability replica does not have a healthy role
                Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-replica-does-not-have-a-healthy-role
                Policy Name: Availability Replica Role State
                Issue: Availability replica does not have a healthy role.
                Category: Critical
                Facet: Availability replica

                Name           : AlwaysOnArReplicaRoleHealthCondition
                Facet          : IAvailabilityReplicaState
                ExpressionNode : @Role = Enum('Microsoft.SqlServer.Management.Smo.AvailabilityReplicaRole', 'Primary') OR @Role = Enum('Microsoft.SqlServer.Management.Smo.AvailabilityReplicaRole', 'Secondary')
                #>

                $isHealthy = $replica.Role -in "Primary", "Secondary"
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    Replica           = $replica.Name
                    Database          = $null
                    PolicyName        = "Availability Replica Role State"
                    Category          = "Critical"
                    Facet             = "Availability replica"
                    IsHealthy         = $isHealthy
                    Issue             = if ($isHealthy) { $null } else { "Availability replica does not have a healthy role." }
                    Details           = "Role is $($replica.Role)"
                }

                <#
                Availability replica is disconnected
                Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-replica-is-disconnected
                Policy Name: Availability Replica Connection State
                Issue: Availability replica is disconnected.
                Category: Critical
                Facet: Availability replica

                Name           : AlwaysOnArReplicaConnectionHealthCondition
                Facet          : IAvailabilityReplicaState
                ExpressionNode : @ConnectionState = Enum('Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionState', 'Connected') OR @Role = Enum('Microsoft.SqlServer.Management.Smo.AvailabilityReplicaRole', 'Primary')
                #>

                $isHealthy = $replica.ConnectionState -eq "Connected" -or $replica.Role -eq "Primary"
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    Replica           = $replica.Name
                    Database          = $null
                    PolicyName        = "Availability Replica Connection State"
                    Category          = "Critical"
                    Facet             = "Availability replica"
                    IsHealthy         = $isHealthy
                    Issue             = if ($isHealthy) { $null } else { "Availability replica is disconnected." }
                    Details           = "ConnectionState is $($replica.ConnectionState), Role is $($replica.Role)"
                }

                <#
                Availability replica is not joined
                Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-replica-is-not-joined
                Policy Name: Availability Replica Joined State
                Issue: Availability replica is not joined.
                Category: Warning
                Facet: Availability replica

                Name           : AlwaysOnArReplicaJoinedHealthCondition
                Facet          : IAvailabilityReplicaState
                ExpressionNode : @JoinState = Enum('Microsoft.SqlServer.Management.Smo.AvailabilityReplicaJoinState', 'JoinedStandaloneInstance') OR @JoinState = Enum('Microsoft.SqlServer.Management.Smo.AvailabilityReplicaJoinState', 'JoinedWindowsServerFailoverCluster')
                #>

                $isHealthy = $replica.JoinState -in "JoinedStandaloneInstance", "JoinedWindowsServerFailoverCluster"
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    Replica           = $replica.Name
                    Database          = $null
                    PolicyName        = "Availability Replica Joined State"
                    Category          = "Warning"
                    Facet             = "Availability replica"
                    IsHealthy         = $isHealthy
                    Issue             = if ($isHealthy) { $null } else { "Availability replica is not joined." }
                    Details           = "JoinState is $($replica.JoinState)"
                }

                $replicaDatabaseReplicaStates = @($ag.DatabaseReplicaStates | Where-Object AvailabilityReplicaId -eq $replica.UniqueId)

                <#
                Data synchronization state of some availability database is not healthy
                Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/data-synchronization-state-of-some-availability-database-is-not-healthy
                Policy Name: Availability Replica Data Synchronization State
                Issue: Data synchronization state of some availability database is not healthy.
                Category: Warning
                Facet: Availability replica
                #>

                if ($replica.AvailabilityMode -eq "SynchronousCommit") {
                    $unhealthyReplicaDatabaseStates = @($replicaDatabaseReplicaStates | Where-Object SynchronizationState -ne "Synchronized")
                } else {
                    $unhealthyReplicaDatabaseStates = @($replicaDatabaseReplicaStates | Where-Object SynchronizationState -eq "NotSynchronizing")
                }
                $isHealthy = $unhealthyReplicaDatabaseStates.Count -eq 0
                if ($replicaDatabaseReplicaStates) {
                    $stateDetails = ($replicaDatabaseReplicaStates | ForEach-Object {
                            "$($_.AvailabilityDatabaseName):$($_.SynchronizationState)"
                        }) -join ", "
                } else {
                    $stateDetails = "No availability database states found"
                }
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    Replica           = $replica.Name
                    Database          = $null
                    PolicyName        = "Availability Replica Data Synchronization State"
                    Category          = "Warning"
                    Facet             = "Availability replica"
                    IsHealthy         = $isHealthy
                    Issue             = if ($isHealthy) { $null } else { "Data synchronization state of some availability database is not healthy." }
                    Details           = "AvailabilityMode is $($replica.AvailabilityMode); SynchronizationState(s): $stateDetails"
                }
            }

            foreach ($databaseReplicaState in $ag.DatabaseReplicaStates) {
                <#
                Data synchronization state of availability database is not healthy
                Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/data-synchronization-state-of-availability-database-is-not-healthy
                Policy Name: Availability Database Data Synchronization State
                Issue: Data synchronization state of availability database is not healthy.
                Category: Warning
                Facet: Availability database

                Name           : AlwaysOnDbDataSynchronizationHealthCondition
                Facet          : IAvailabilityDatabaseState
                Expected State : Synchronized for synchronous-commit replicas, Synchronizing for all others
                #>

                if ($databaseReplicaState.ReplicaAvailabilityMode -eq "SynchronousCommit") {
                    $isHealthy = $databaseReplicaState.SynchronizationState -eq "Synchronized"
                } else {
                    $isHealthy = $databaseReplicaState.SynchronizationState -eq "Synchronizing"
                }
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    Replica           = $databaseReplicaState.AvailabilityReplicaServerName
                    Database          = $databaseReplicaState.AvailabilityDatabaseName
                    PolicyName        = "Availability Database Data Synchronization State"
                    Category          = "Warning"
                    Facet             = "Availability database"
                    IsHealthy         = $isHealthy
                    Issue             = if ($isHealthy) { $null } else { "Data synchronization state of availability database is not healthy." }
                    Details           = "SynchronizationState is $($databaseReplicaState.SynchronizationState), ReplicaAvailabilityMode is $($databaseReplicaState.ReplicaAvailabilityMode)"
                }

                <#
                Availability database is suspended
                Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-database-is-suspended
                Policy Name: Availability Database Suspension State
                Issue: Availability database is suspended.
                Category: Warning
                Facet: Availability database

                Name           : AlwaysOnDbSuspendedHealthCondition
                Facet          : IAvailabilityDatabaseState
                ExpressionNode : @IsSuspended = False()
                #>

                $isHealthy = -not $databaseReplicaState.IsSuspended
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    Replica           = $databaseReplicaState.AvailabilityReplicaServerName
                    Database          = $databaseReplicaState.AvailabilityDatabaseName
                    PolicyName        = "Availability Database Suspension State"
                    Category          = "Warning"
                    Facet             = "Availability database"
                    IsHealthy         = $isHealthy
                    Issue             = if ($isHealthy) { $null } else { "Availability database is suspended." }
                    Details           = "IsSuspended is $($databaseReplicaState.IsSuspended)"
                }

                <#
                Availability database is not joined to the availability group
                Documentation: https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/secondary-database-is-not-joined
                Policy Name: Availability Database Join State
                Issue: Secondary database is not joined.
                Category: Warning
                Facet: Availability database

                Name           : AlwaysOnDbJoinedHealthCondition
                Facet          : IAvailabilityDatabaseState
                ExpressionNode : @IsJoined = True()
                #>

                $isHealthy = $databaseReplicaState.IsJoined
                [PSCustomObject]@{
                    ComputerName      = $ag.ComputerName
                    InstanceName      = $ag.InstanceName
                    SqlInstance       = $ag.SqlInstance
                    AvailabilityGroup = $ag.Name
                    Replica           = $databaseReplicaState.AvailabilityReplicaServerName
                    Database          = $databaseReplicaState.AvailabilityDatabaseName
                    PolicyName        = "Availability Database Join State"
                    Category          = "Warning"
                    Facet             = "Availability database"
                    IsHealthy         = $isHealthy
                    Issue             = if ($isHealthy) { $null } else { "Availability database is not joined to the availability group." }
                    Details           = "IsJoined is $($databaseReplicaState.IsJoined)"
                }
            }
        }
    }
} $SqlInstance $SqlCredential $AvailabilityGroup $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}