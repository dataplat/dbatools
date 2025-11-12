function Get-DbaAgDatabaseReplicaState {
    <#
    .SYNOPSIS
        Retrieves the runtime state of databases participating in availability groups across all replicas.

    .DESCRIPTION
        Retrieves comprehensive health monitoring information about databases participating in SQL Server availability groups, similar to the SSMS AG Dashboard. This function returns detailed database replica state information for all replicas in the availability group.

        The class Microsoft.SqlServer.Management.Smo.DatabaseReplicaState represents the runtime state of a database that's participating in an availability group. This database may be located on any of the replicas that compose the availability group.

        Use this command to monitor availability group health, troubleshoot synchronization issues, verify failover readiness, identify data loss risks, and generate detailed operational reports showing the state of each database on each replica in your availability groups.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies which availability groups to query for database replica state information. Accepts multiple availability group names.
        Use this to limit results to specific availability groups when you have multiple AGs on the same instance.

    .PARAMETER Database
        Specifies which availability group databases to return replica state information for. Accepts multiple database names.
        Use this to focus on specific databases when troubleshooting AG issues or monitoring particular applications.

    .PARAMETER InputObject
        Accepts availability group objects from Get-DbaAvailabilityGroup via pipeline input.
        Use this when you want to chain commands to get database replica state details from already retrieved availability groups.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA, Monitoring, Health
        Author: Andreas Jordan (@andreasjordan)

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgDatabaseReplicaState

    .EXAMPLE
        PS C:\> Get-DbaAgDatabaseReplicaState -SqlInstance sql2017a

        Returns database replica state information for all databases in all availability groups on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAgDatabaseReplicaState -SqlInstance sql2017a -AvailabilityGroup AG101

        Returns database replica state information for all databases in the availability group AG101 on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAgDatabaseReplicaState -SqlInstance sql2017a -AvailabilityGroup AG101 -Database AppDB

        Returns database replica state information for the AppDB database in the availability group AG101 on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlcluster -AvailabilityGroup SharePoint | Get-DbaAgDatabaseReplicaState

        Returns database replica state information for all databases in the availability group SharePoint on server sqlcluster

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlcluster -AvailabilityGroup SharePoint | Get-DbaAgDatabaseReplicaState -Database Sharepoint_Config

        Returns database replica state information for the Sharepoint_Config database in the availability group SharePoint on server sqlcluster
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($ag in $InputObject) {
            # Comprehensive health monitoring similar to SSMS AG Dashboard
            # Returns detailed database replica state information for all replicas
            foreach ($replica in $ag.AvailabilityReplicas) {
                $replicaId = $replica.UniqueId
                $replicaStates = $ag.DatabaseReplicaStates | Where-Object AvailabilityReplicaId -eq $replicaId

                foreach ($db in $ag.AvailabilityDatabases) {
                    if ($Database) {
                        if ($db.Name -notin $Database) { continue }
                    }

                    # AvailabilityDateabaseId is a typo in SMO but we have to use it as-is
                    # See https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.databasereplicastate.availabilitydateabaseid
                    $databaseReplicaState = $replicaStates | Where-Object AvailabilityDateabaseId -eq $db.UniqueId
                    if ($null -eq $databaseReplicaState) {
                        continue
                    }

                    [PSCustomObject]@{
                        ComputerName                = $ag.ComputerName
                        InstanceName                = $ag.InstanceName
                        SqlInstance                 = $ag.SqlInstance
                        AvailabilityGroup           = $ag.Name
                        PrimaryReplica              = $ag.PrimaryReplica
                        ReplicaServerName           = $databaseReplicaState.AvailabilityReplicaServerName
                        ReplicaRole                 = $databaseReplicaState.ReplicaRole
                        ReplicaAvailabilityMode     = $replica.AvailabilityMode
                        ReplicaFailoverMode         = $replica.FailoverMode
                        ReplicaConnectionState      = $replica.ConnectionState
                        ReplicaJoinState            = $replica.JoinState
                        ReplicaSynchronizationState = $replica.RollupSynchronizationState
                        DatabaseName                = $databaseReplicaState.AvailabilityDatabaseName
                        SynchronizationState        = $databaseReplicaState.SynchronizationState
                        IsFailoverReady             = $databaseReplicaState.IsFailoverReady
                        IsJoined                    = $databaseReplicaState.IsJoined
                        IsSuspended                 = $databaseReplicaState.IsSuspended
                        SuspendReason               = $databaseReplicaState.SuspendReason
                        EstimatedRecoveryTime       = $databaseReplicaState.EstimatedRecoveryTime
                        EstimatedDataLoss           = $databaseReplicaState.EstimatedDataLoss
                        SynchronizationPerformance  = $databaseReplicaState.SynchronizationPerformance
                        LogSendQueueSize            = $databaseReplicaState.LogSendQueueSize
                        LogSendRate                 = $databaseReplicaState.LogSendRate
                        RedoQueueSize               = $databaseReplicaState.RedoQueueSize
                        RedoRate                    = $databaseReplicaState.RedoRate
                        FileStreamSendRate          = $databaseReplicaState.FileStreamSendRate
                        EndOfLogLSN                 = $databaseReplicaState.EndOfLogLSN
                        RecoveryLSN                 = $databaseReplicaState.RecoveryLSN
                        TruncationLSN               = $databaseReplicaState.TruncationLSN
                        LastCommitLSN               = $databaseReplicaState.LastCommitLSN
                        LastCommitTime              = $databaseReplicaState.LastCommitTime
                        LastHardenedLSN             = $databaseReplicaState.LastHardenedLSN
                        LastHardenedTime            = $databaseReplicaState.LastHardenedTime
                        LastReceivedLSN             = $databaseReplicaState.LastReceivedLSN
                        LastReceivedTime            = $databaseReplicaState.LastReceivedTime
                        LastRedoneLSN               = $databaseReplicaState.LastRedoneLSN
                        LastRedoneTime              = $databaseReplicaState.LastRedoneTime
                        LastSentLSN                 = $databaseReplicaState.LastSentLSN
                        LastSentTime                = $databaseReplicaState.LastSentTime
                    }
                }
            }
        }
    }
}
