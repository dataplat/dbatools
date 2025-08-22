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
        The replicas to modify.

    .PARAMETER AvailabilityGroup
        The availability group of the replica.

    .PARAMETER AvailabilityMode
        Sets the availability mode of the availability group replica. Options are: AsynchronousCommit and SynchronousCommit. SynchronousCommit is default.

    .PARAMETER FailoverMode
        Sets the failover mode of the availability group replica. Options are Automatic and Manual.

    .PARAMETER BackupPriority
        Sets the backup priority availability group replica. Default is 50.

    .PARAMETER EndpointUrl
        The endpoint URL.

    .PARAMETER InputObject
        Enables piping from Get-DbaAgReplica.

    .PARAMETER ConnectionModeInPrimaryRole
        Sets the connection intent modes of an Availability Replica in primary role.

    .PARAMETER ConnectionModeInSecondaryRole
        Sets the connection modes of an Availability Replica in secondary role.

    .PARAMETER ReadonlyRoutingConnectionUrl
        Sets the read only routing connection url for the availability replica.

    .PARAMETER ReadOnlyRoutingList
        Sets the read-only routing list for when this replica is in the primary role.

    .PARAMETER SeedingMode
        Specifies how the secondary replica will be initially seeded.

        Automatic enables direct seeding. This method will seed the secondary replica over the network. This method does not require you to backup and restore a copy of the primary database on the replica.

        Manual requires you to create a backup of the database on the primary replica and manually restore that backup on the secondary replica.

    .PARAMETER SessionTimeout
        How many seconds an availability replica waits for a ping response from a connected replica before considering the connection to have failed.

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
                        $rorl = New-Object System.Collections.Generic.List[System.Collections.Generic.IList[string]]
                        foreach ($rolist in $ReadOnlyRoutingList) {
                            $null = $rorl.Add([System.Collections.Generic.List[string]] $rolist)
                        }
                        $null = $agreplica.SetLoadBalancedReadOnlyRoutingList($rorl)
                    }

                    if ($SessionTimeout) {
                        if ($SessionTimeout -lt 10) {
                            $Message = "We recommend that you keep the time-out period at 10 seconds or greater. Setting the value to less than 10 seconds creates the possibility of a heavily loaded system missing pings and falsely declaring failure. Please see sqlps.io/agrec for more information."
                            Write-Message -Message $Message -Level Warning
                        }
                        $agreplica.SessionTimeout = $SessionTimeout
                    }

                    $agreplica.Alter()
                    $agreplica

                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}