function Set-DbaAgReplica {
    <#
    .SYNOPSIS
        Modifies configuration properties of existing availability group replicas.

    .DESCRIPTION
        Modifies configuration properties of existing availability group replicas such as availability mode, failover behavior, backup priority, and read-only routing settings. This function is used for ongoing management and tuning of availability groups after initial setup, allowing you to adjust replica behavior without recreating the availability group.

        Common use cases include changing synchronous replicas to asynchronous for performance, adjusting backup priorities to control where backups run, configuring automatic failover settings, and setting up read-only routing for load balancing read workloads across secondary replicas.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Replica
        Specifies the name of the availability group replica to modify. This is the server instance name that hosts the replica.
        Use this when targeting a specific replica within an availability group for configuration changes.

    .PARAMETER AvailabilityGroup
        Specifies the name of the availability group that contains the replica to modify.
        Required when using SqlInstance parameter to identify which availability group the replica belongs to.

    .PARAMETER AvailabilityMode
        Controls the data synchronization mode between primary and secondary replicas. SynchronousCommit ensures zero data loss but may impact performance, while AsynchronousCommit prioritizes performance over guaranteed data protection.
        Change this when you need to balance performance requirements against data protection needs across different replicas.

    .PARAMETER FailoverMode
        Determines whether the replica can automatically failover when the primary becomes unavailable. Automatic failover requires SynchronousCommit availability mode and is typically used for high availability scenarios.
        Set to Manual when you want to control failover decisions or when using AsynchronousCommit replicas.

    .PARAMETER BackupPriority
        Sets the backup priority for this replica on a scale of 0-100, where higher values indicate higher priority for backup operations.
        Use this to control which replica should be preferred for automated backup jobs, with 0 excluding the replica from backup consideration entirely.

    .PARAMETER EndpointUrl
        Specifies the URL endpoint used for data mirroring communication between replicas, typically in the format 'TCP://servername:port'.
        Update this when changing network configurations, server names, or port assignments for availability group communication.

    .PARAMETER InputObject
        Accepts availability group replica objects from Get-DbaAgReplica for pipeline operations.
        Use this to modify multiple replicas or when working with replica objects retrieved from previous commands.

    .PARAMETER ConnectionModeInPrimaryRole
        Controls what types of connections are allowed when this replica is the primary. AllowAllConnections permits both read-write and read-only connections, while AllowReadWriteConnections only allows read-write access.
        Typically left as AllowAllConnections unless you need to restrict read-only workloads from connecting to the primary.

    .PARAMETER ConnectionModeInSecondaryRole
        Determines connection access when this replica is secondary. Options include AllowNoConnections, AllowReadIntentConnectionsOnly (for read-only workloads), or AllowAllConnections.
        Configure this to enable read-only workloads on secondary replicas for reporting or to completely block connections for backup-only replicas.

    .PARAMETER ReadonlyRoutingConnectionUrl
        Specifies the connection string used by the availability group listener to route read-only connections to this secondary replica.
        Required when setting up read-only routing to distribute read workloads across secondary replicas for load balancing.

    .PARAMETER ReadOnlyRoutingList
        Defines the ordered list of secondary replicas that should receive read-only connections when this replica is primary. Accepts arrays for load-balanced routing or simple arrays for priority-based routing.
        Use this to establish read-only routing policies that distribute read workloads across available secondary replicas.

    .PARAMETER SeedingMode
        Controls the database initialization method for new databases added to the availability group. Automatic performs direct seeding over the network without manual backup/restore steps, while Manual requires traditional backup and restore operations.
        Choose Automatic for convenience and reduced administrative overhead, or Manual when you need control over backup/restore timing or have network bandwidth constraints.

    .PARAMETER SessionTimeout
        Sets the timeout period in seconds for detecting communication failures between availability replicas. Values below 10 seconds can cause false failure detection in busy environments.
        Increase this value in high-latency network environments or decrease it when you need faster failure detection, keeping the 10-second minimum recommendation in mind.

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
        https://dbatools.io/Set-DbaAgReplica

    .EXAMPLE
        PS C:\> Set-DbaAgReplica -SqlInstance sql2016 -Replica sql2016 -AvailabilityGroup SharePoint -BackupPriority 5000

        Sets the backup priority to 5000 for the sql2016 replica for the SharePoint availability group on sql2016

    .EXAMPLE
        PS C:\> Get-DbaAgReplica -SqlInstance sql2016 | Out-GridView -Passthru | Set-DbaAgReplica -BackupPriority 5000

        Sets the backup priority to 5000 for the selected availability groups.

    .EXAMPLE
        PS C:\> Get-DbaAgReplica -SqlInstance sql2016 -Replica Replica1 |
        >> Set-DbaAgReplica -ReadOnlyRoutingList Replica2, Replica3

        Equivalent to running "ALTER AVAILABILITY GROUP... MODIFY REPLICA... (READ_ONLY_ROUTING_LIST = ('Replica2', 'Replica3'));"

    .EXAMPLE
        PS C:\> Get-DbaAgReplica -SqlInstance sql2016 -Replica Replica1 |
        >> Set-DbaAgReplica -ReadOnlyRoutingList @(,('Replica2','Replica3'));

        Equivalent to running "ALTER AVAILABILITY GROUP... MODIFY REPLICA... (READ_ONLY_ROUTING_LIST = (('Replica2', 'Replica3')));" setting a load balanced routing list for when Replica1 is the primary replica.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$AvailabilityGroup,
        [string]$Replica,
        [ValidateSet('AsynchronousCommit', 'SynchronousCommit')]
        [string]$AvailabilityMode,
        [ValidateSet('Automatic', 'Manual', 'External')]
        [string]$FailoverMode,
        [int]$BackupPriority,
        [ValidateSet('AllowAllConnections', 'AllowReadWriteConnections')]
        [string]$ConnectionModeInPrimaryRole,
        [ValidateSet('AllowAllConnections', 'AllowNoConnections', 'AllowReadIntentConnectionsOnly', 'No', 'Read-intent only', 'Yes')]
        [string]$ConnectionModeInSecondaryRole,
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode,
        [int]$SessionTimeout,
        [string]$EndpointUrl,
        [string]$ReadonlyRoutingConnectionUrl,
        [object[]]$ReadOnlyRoutingList,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityReplica]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ($ReadOnlyRoutingList) {
            $null = Add-Type -AssemblyName System.Collections
        }
    }
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if (-not $InputObject) {
            if (-not $AvailabilityGroup -or -not $Replica) {
                Stop-Function -Message "You must specify an AvailabilityGroup and replica or pipe in an availabilty group to continue."
                return
            }
        }

        if ($ConnectionModeInSecondaryRole) {
            $ConnectionModeInSecondaryRole =
            switch ($ConnectionModeInSecondaryRole) {
                "No" { "AllowNoConnections" }
                "Read-intent only" { "AllowReadIntentConnectionsOnly" }
                "Yes" { "AllowAllConnections" }
                default { $ConnectionModeInSecondaryRole }
            }
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAgReplica -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup -Replica $Replica
        }

        foreach ($agreplica in $InputObject) {
            $server = $agreplica.Parent.Parent
            if ($Pscmdlet.ShouldProcess($server.Name, "Modifying replica for $($agreplica.Name) named $Name")) {
                try {
                    if ($EndpointUrl) {
                        $agreplica.EndpointUrl = $EndpointUrl
                    }

                    if ($FailoverMode) {
                        $agreplica.FailoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::$FailoverMode
                    }

                    if ($AvailabilityMode) {
                        $agreplica.AvailabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::$AvailabilityMode
                    }

                    if ($ConnectionModeInPrimaryRole) {
                        $agreplica.ConnectionModeInPrimaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInPrimaryRole]::$ConnectionModeInPrimaryRole
                    }

                    if ($ConnectionModeInSecondaryRole) {
                        $agreplica.ConnectionModeInSecondaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInSecondaryRole]::$ConnectionModeInSecondaryRole
                    }

                    if ($BackupPriority) {
                        $agreplica.BackupPriority = $BackupPriority
                    }

                    if ($ReadonlyRoutingConnectionUrl) {
                        $agreplica.ReadonlyRoutingConnectionUrl = $ReadonlyRoutingConnectionUrl
                    }

                    if ($SeedingMode) {
                        $agreplica.SeedingMode = $SeedingMode
                    }

                    if ($ReadOnlyRoutingList) {
                        # Detect if this is a simple ordered list or a load-balanced (nested) list
                        # Simple list: @('Server1', 'Server2') - routes in order, SQL: ('Server1', 'Server2')
                        # Load-balanced list: @(,('Server1', 'Server2')) - load balances, SQL: (('Server1', 'Server2'))
                        $isLoadBalanced = $false

                        # Check if the first element is an array/list (indicates load-balanced routing)
                        if ($ReadOnlyRoutingList.Count -gt 0 -and $ReadOnlyRoutingList[0] -is [System.Array]) {
                            $isLoadBalanced = $true
                        }

                        if ($isLoadBalanced) {
                            # Load-balanced routing - use SetLoadBalancedReadOnlyRoutingList method
                            $rorl = New-Object System.Collections.Generic.List[System.Collections.Generic.IList[string]]
                            foreach ($rolist in $ReadOnlyRoutingList) {
                                $null = $rorl.Add([System.Collections.Generic.List[string]] $rolist)
                            }
                            $null = $agreplica.SetLoadBalancedReadOnlyRoutingList($rorl)
                        } else {
                            # Simple ordered routing - use property assignment
                            # This is the standard approach for ordered routing lists
                            $agreplica.ReadonlyRoutingList.Clear()
                            foreach ($server in $ReadOnlyRoutingList) {
                                $null = $agreplica.ReadonlyRoutingList.Add([string]$server)
                            }
                        }
                    }

                    if ($SessionTimeout) {
                        if ($SessionTimeout -lt 10) {
                            $Message = "We recommend that you keep the time-out period at 10 seconds or greater. Setting the value to less than 10 seconds creates the possibility of a heavily loaded system missing pings and falsely declaring failure. Please see sqlps.io/agrec for more information."
                            Write-Message -Message $Message -Level Warning
                        }
                        $agreplica.SessionTimeout = $SessionTimeout
                    }

                    $agreplica.Alter()
                    # Refresh the parent's replica collection to get updated ReadonlyRoutingList
                    $agreplica.Parent.AvailabilityReplicas.Refresh()
                    $agreplica.Parent.AvailabilityReplicas[$agreplica.Name]

                } catch {
                    Stop-Function -Message "Failed to modify replica $($agreplica.Name) in availability group $($agreplica.Parent.Name)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}