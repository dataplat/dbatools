function Get-DbaAgDatabase {
    <#
    .SYNOPSIS
        Retrieves availability group database information and synchronization status from SQL Server instances.

    .DESCRIPTION
        Retrieves detailed information about databases participating in SQL Server availability groups, including their synchronization state, failover readiness, and replica-specific status. This function queries the availability group configuration from each SQL Server instance to return database-level health and status information that varies depending on whether the replica is primary or secondary.

        Use this command to monitor availability group database health, troubleshoot synchronization issues, verify failover readiness, or generate compliance reports showing which databases are properly synchronized across your availability group replicas. The returned data includes critical operational details like suspension status, join state, and synchronization health that help DBAs quickly identify databases requiring attention.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies which availability groups to query for database information. Accepts multiple availability group names.
        Use this to limit results to specific availability groups when you have multiple AGs on the same instance.

    .PARAMETER Database
        Specifies which availability group databases to return information for. Accepts multiple database names with tab completion.
        Use this to focus on specific databases when troubleshooting AG issues or monitoring particular applications.

    .PARAMETER InputObject
        Accepts availability group objects from Get-DbaAvailabilityGroup via pipeline input.
        Use this when you want to chain commands to get database details from already retrieved availability groups.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgDatabase

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.AvailabilityDatabase

        Returns one AvailabilityDatabase object for each database found in the availability groups on the specified instances.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - AvailabilityGroup: Name of the availability group
        - LocalReplicaRole: Role of this replica (Primary or Secondary)
        - Name: Database name
        - SynchronizationState: Current synchronization state (NotSynchronizing, Synchronizing, Synchronized, Reverting, Initializing)
        - IsFailoverReady: Boolean indicating if the database is ready for failover
        - IsJoined: Boolean indicating if the database has joined the availability group
        - IsSuspended: Boolean indicating if data movement is suspended

        Additional properties available (from SMO AvailabilityDatabase object):
        - DatabaseGuid: Unique identifier for the database
        - EstimatedDataLoss: Estimated data loss in seconds
        - EstimatedRecoveryTime: Estimated recovery time in seconds
        - FileStreamSendRate: Rate of FILESTREAM data being sent (bytes/sec)
        - GroupDatabaseId: Unique identifier for the database within the AG
        - ID: Internal object ID
        - IsAvailabilityDatabaseSuspended: Boolean indicating suspension state
        - IsDatabaseDiskHealthy: Boolean indicating if database disk health is good
        - IsDatabaseJoined: Boolean indicating database join state
        - IsInstanceDiskHealthy: Boolean indicating if instance disk health is good
        - IsInstanceHealthy: Boolean indicating overall instance health
        - IsPendingSecondarySuspend: Boolean indicating if secondary suspend is pending
        - LastCommitLsn: Last commit log sequence number
        - LastCommitTime: Timestamp of last committed transaction
        - LastHardenedLsn: Last hardened log sequence number
        - LastHardenedTime: Timestamp when last LSN was hardened
        - LastReceivedLsn: Last received log sequence number
        - LastReceivedTime: Timestamp when last LSN was received
        - LastRedoneLsn: Last redone log sequence number
        - LastRedoneTime: Timestamp when last LSN was redone
        - LastSentLsn: Last sent log sequence number
        - LastSentTime: Timestamp when last LSN was sent
        - LogSendQueue: Size of log send queue in KB
        - LogSendRate: Rate of log sending (bytes/sec)
        - LowWaterMarkForGhostCleanup: Low water mark LSN for ghost cleanup
        - Parent: Reference to parent AvailabilityGroup SMO object
        - RecoveryLsn: Recovery log sequence number
        - RedoQueue: Size of redo queue in KB
        - RedoRate: Rate of redo operations (bytes/sec)
        - SecondaryLagSeconds: Lag in seconds for secondary replica
        - State: SMO object state (Existing, Creating, Pending, etc.)
        - SuspendReason: Reason for suspension if database is suspended
        - Urn: Uniform Resource Name for the SMO object

    .EXAMPLE
        PS C:\> Get-DbaAgDatabase -SqlInstance sql2017a

        Returns all the databases in each availability group found on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAgDatabase -SqlInstance sql2017a -AvailabilityGroup AG101

        Returns all the databases in the availability group AG101 on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlcluster -AvailabilityGroup SharePoint | Get-DbaAgDatabase -Database Sharepoint_Config

        Returns the database Sharepoint_Config found in the availability group SharePoint on server sqlcluster
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

        foreach ($db in $InputObject.AvailabilityDatabases) {
            if ($Database) {
                if ($db.Name -notin $Database) { continue }
            }
            $ag = $db.Parent
            $server = $db.Parent.Parent
            Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
            Add-Member -Force -InputObject $db -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
            Add-Member -Force -InputObject $db -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
            Add-Member -Force -InputObject $db -MemberType NoteProperty -Name AvailabilityGroup -Value $ag.Name
            Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LocalReplicaRole -Value $ag.LocalReplicaRole

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'LocalReplicaRole', 'Name', 'SynchronizationState', 'IsFailoverReady', 'IsJoined', 'IsSuspended'
            Select-DefaultView -InputObject $db -Property $defaults
        }
    }
}