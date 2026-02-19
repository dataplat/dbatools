function Invoke-DbaAgFailover {
    <#
    .SYNOPSIS
        Performs manual failover of an availability group to make the target instance the new primary replica.

    .DESCRIPTION
        Performs manual failover of an availability group to make the specified SQL Server instance the new primary replica. The function connects to the target instance (which must be a secondary replica) and promotes it to primary, while the current primary becomes secondary.

        By default, performs a safe failover that waits for all committed transactions to be synchronized to the target replica, preventing data loss. When the -Force parameter is used, performs a forced failover that may result in data loss if transactions haven't been synchronized to the target replica.

        This is commonly used during planned maintenance windows, disaster recovery scenarios, or when rebalancing availability group workloads across replicas. The target instance must already be configured as a secondary replica in the availability group.

    .PARAMETER SqlInstance
        The SQL Server instance. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER AvailabilityGroup
        Specifies the name(s) of the availability groups to failover on the target instance. Accepts multiple availability group names.
        Use this when you need to failover specific availability groups rather than all groups on the instance.
        Required when using SqlInstance parameter to identify which availability groups should be failed over.

    .PARAMETER InputObject
        Accepts availability group objects from Get-DbaAvailabilityGroup for pipeline operations.
        Use this approach when you want to filter or select specific availability groups before failover.
        Allows for more complex scenarios like failing over multiple groups across different instances in a single operation.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Performs a forced failover that allows potential data loss by not waiting for transaction synchronization.
        Use this during disaster recovery scenarios when the primary replica is unavailable and you need immediate failover.
        Without this switch, the function performs a safe failover that waits for all committed transactions to synchronize, preventing data loss.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.AvailabilityGroup

        Returns one AvailabilityGroup object per availability group that was failed over. The object reflects the new state after the failover operation completes.

        Default properties visible when displayed:
        - Name: The name of the availability group
        - PrimaryReplicaServerName: The server hosting the primary replica after failover
        - LocalReplicaRole: The role of the local replica (Primary or Secondary)
        - AutomatedBackupPreference: Preference for which replicas perform backups (Primary, Secondary, etc.)
        - FailureConditionLevel: The condition level that triggers automatic failover
        - HealthCheckTimeout: The health check interval in milliseconds
        - BasicAvailabilityGroup: Boolean indicating if this is a basic (Enterprise-only) availability group
        - ClusterType: The cluster type used (WSFC, External, or None)

        Additional properties available from the SMO AvailabilityGroup object:
        - ID: Unique identifier for the availability group
        - UniqueId: The globally unique identifier for the availability group
        - AvailabilityReplicas: Collection of all replica objects in the availability group
        - AvailabilityDatabases: Collection of databases participating in the availability group
        - AvailabilityGroupListeners: Collection of listener endpoints configured for the availability group
        - DatabaseReplicaStates: Collection of database states across all replicas
        - RequiredSynchronizedSecondariesToCommit: Number of secondaries that must be synchronized before commit

        Use Select-Object * to access all SMO properties available on the AvailabilityGroup object.

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaAgFailover

    .EXAMPLE
        PS C:\> Invoke-DbaAgFailover -SqlInstance sql2017 -AvailabilityGroup SharePoint

        Safely (no potential data loss) fails over the SharePoint AG to sql2017. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017 | Out-GridView -Passthru | Invoke-DbaAgFailover -Confirm:$false

        Safely (no potential data loss) fails over the selected availability groups to sql2017. Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Invoke-DbaAgFailover -SqlInstance sql2017 -AvailabilityGroup SharePoint -Force

        Forcefully (with potential data loss) fails over the SharePoint AG to sql2017. Prompts for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ($SqlInstance -and -not $AvailabilityGroup) {
            Stop-Function -Message "You must specify at least one availability group when using SqlInstance."
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($ag in $InputObject) {
            try {
                $server = $ag.Parent
                if ($Force) {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Forcefully failing over $($ag.Name), allowing potential data loss")) {
                        $ag.FailoverWithPotentialDataLoss()
                        $ag.Refresh()
                        $ag
                    }
                } else {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Gracefully failing over $($ag.Name)")) {
                        $ag.Failover()
                        $ag.Refresh()
                        $ag
                    }
                }
            } catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_
            }
        }
    }
}