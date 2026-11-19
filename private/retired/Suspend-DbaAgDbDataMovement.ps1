function Suspend-DbaAgDbDataMovement {
    <#
    .SYNOPSIS
        Suspends data synchronization for availability group databases to halt replication between replicas.

    .DESCRIPTION
        Temporarily halts data movement between primary and secondary replicas for specified availability group databases. This stops transaction log records from being sent to secondary replicas, which is useful during maintenance windows, troubleshooting synchronization issues, or when preparing for manual failovers. While suspended, the secondary databases will fall behind the primary and cannot be failed over to until data movement is resumed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which availability group databases to suspend data movement for. Accepts multiple database names.
        Use this when you need to halt synchronization for specific databases while leaving other AG databases running normally.

    .PARAMETER AvailabilityGroup
        Specifies the availability group containing the databases to suspend. Required when using SqlInstance parameter.
        Use this to target databases within a specific AG when multiple availability groups exist on the instance.

    .PARAMETER InputObject
        Accepts availability group database objects piped from Get-DbaAgDatabase or other dbatools AG commands.
        Use this for pipeline operations when you want to filter and select specific AG databases before suspending data movement.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Suspend-DbaAgDbDataMovement

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.AvailabilityDatabase

        Returns one AvailabilityDatabase object for each database where data movement was suspended. When suspending data movement for multiple databases, one object is returned per database.

        Default display properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - AvailabilityGroup: Name of the availability group
        - LocalReplicaRole: Role of this replica (Primary or Secondary)
        - Name: Database name
        - SynchronizationState: Current synchronization state (NotSynchronizing, Synchronizing, Synchronized, Reverting, Initializing)
        - IsFailoverReady: Boolean indicating if the database is ready for failover
        - IsJoined: Boolean indicating if the database has joined the availability group
        - IsSuspended: Boolean indicating if data movement is suspended (true after suspension completes)

        Additional properties available on the SMO AvailabilityDatabase object (via Select-Object *):
        - DatabaseGuid: Unique identifier for the database
        - EstimatedDataLoss: Estimated data loss in seconds
        - EstimatedRecoveryTime: Estimated recovery time in seconds
        - FileStreamSendRate: Rate of FILESTREAM data being sent (bytes/sec)
        - GroupDatabaseId: Unique identifier for the database within the AG
        - LastCommitTime: Timestamp of last committed transaction
        - LogSendQueue: Size of log send queue in KB
        - RedoRate: Rate of redo operations (bytes/sec)

    .EXAMPLE
        PS C:\> Suspend-DbaAgDbDataMovement -SqlInstance sql2017a -AvailabilityGroup ag1 -Database db1, db2

        Suspends data movement on db1 and db2 to ag1 on sql2017a. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaAgDatabase -SqlInstance sql2017a, sql2019 | Out-GridView -Passthru | Suspend-DbaAgDbDataMovement -Confirm:$false

        Suspends data movement on the selected availability group databases. Does not prompt for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$AvailabilityGroup,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityDatabase[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ((Test-Bound -ParameterName SqlInstance)) {
            if ((Test-Bound -Not -ParameterName Database) -and (Test-Bound -Not -ParameterName AvailabilityGroup)) {
                Stop-Function -Message "You must specify one or more databases and one Availability Groups when using the SqlInstance parameter."
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaAgDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($agdb in $InputObject) {
            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Seting availability group $db to $($db.Parent.Name)")) {
                try {
                    $null = $agdb.SuspendDataMovement()
                    $agdb
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}