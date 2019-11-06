function Add-DbaAgReplica {
    <#
    .SYNOPSIS
        Adds a replica to an availability group on a SQL Server instance.

    .DESCRIPTION
        Adds a replica to an availability group on a SQL Server instance.

        Automatically creates a database mirroring endpoint if required.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The name of the replica. Defaults to the SQL Server instance name.

    .PARAMETER AvailabilityMode
        Sets the availability mode of the availability group replica. Options are: AsynchronousCommit and SynchronousCommit. SynchronousCommit is default.

    .PARAMETER FailoverMode
        Sets the failover mode of the availability group replica. Options are Automatic and Manual. Automatic is default.

    .PARAMETER BackupPriority
        Sets the backup priority availability group replica. Default is 50.

    .PARAMETER Endpoint
        By default, this command will attempt to find a DatabaseMirror endpoint. If one does not exist, it will create it.

        If an endpoint must be created, the name "hadr_endpoint" will be used. If an alternative is preferred, use Endpoint.

    .PARAMETER Passthru
        Don't create the replica, just pass thru an object that can be further customized before creation.

    .PARAMETER InputObject
        Enables piping from Get-DbaAvailabilityGroup.

    .PARAMETER ConnectionModeInPrimaryRole
        Specifies the connection intent modes of an Availability Replica in primary role. AllowAllConnections by default.

    .PARAMETER ConnectionModeInSecondaryRole
        Specifies the connection modes of an Availability Replica in secondary role. AllowAllConnections by default.

    .PARAMETER ReadonlyRoutingConnectionUrl
        Sets the read only routing connection url for the availability replica.

    .PARAMETER SeedingMode
        Specifies how the secondary replica will be initially seeded.

        Automatic enables direct seeding. This method will seed the secondary replica over the network. This method does not require you to backup and restore a copy of the primary database on the replica.

        Manual requires you to create a backup of the database on the primary replica and manually restore that backup on the secondary replica.

    .PARAMETER Certificate
        Specifies that the endpoint is to authenticate the connection using the certificate specified by certificate_name to establish identity for authorization.

        The far endpoint must have a certificate with the public key matching the private key of the specified certificate.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaAgReplica

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup SharePoint | Add-DbaAgReplica -SqlInstance sql2017b

        Adds sql2017b to the SharePoint availability group on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup SharePoint | Add-DbaAgReplica -SqlInstance sql2017b -FailoverMode Manual

        Adds sql2017b to the SharePoint availability group on sql2017a with a manual failover mode.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Name,
        [ValidateSet('AsynchronousCommit', 'SynchronousCommit')]
        [string]$AvailabilityMode = "SynchronousCommit",
        [ValidateSet('Automatic', 'Manual', 'External')]
        [string]$FailoverMode = "Automatic",
        [int]$BackupPriority = 50,
        [ValidateSet('AllowAllConnections', 'AllowReadWriteConnections')]
        [string]$ConnectionModeInPrimaryRole = 'AllowAllConnections',
        [ValidateSet('AllowAllConnections', 'AllowNoConnections', 'AllowReadIntentConnectionsOnly')]
        [string]$ConnectionModeInSecondaryRole = 'AllowAllConnections',
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode,
        [string]$Endpoint,
        [switch]$Passthru,
        [string]$ReadonlyRoutingConnectionUrl,
        [string]$Certificate,
        [parameter(ValueFromPipeline, Mandatory)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Certificate) {
                $cert = Get-DbaDbCertificate -SqlInstance $server -Certificate $Certificate
                if (-not $cert) {
                    Stop-Function -Message "Certificate $Certificate does not exist on $instance" -ErrorRecord $_ -Target $Certificate -Continue
                }
            }

            $ep = Get-DbaEndpoint -SqlInstance $server -Type DatabaseMirroring

            if (-not $ep) {
                if ($Pscmdlet.ShouldProcess($server.Name, "Adding endpoint named $Endpoint to $instance")) {
                    if (-not $Endpoint) {
                        $Endpoint = "hadr_endpoint"
                    }
                    $ep = New-DbaEndpoint -SqlInstance $server -Name hadr_endpoint -Type DatabaseMirroring -EndpointEncryption Supported -EncryptionAlgorithm Aes -Certificate $Certificate
                    $null = $ep | Start-DbaEndpoint
                }
            }

            if ((Test-Bound -Not -ParameterName Name)) {
                $Name = $server.DomainInstanceName
            }

            if ($Pscmdlet.ShouldProcess($server.Name, "Creating a replica for $($InputObject.Name) named $Name")) {
                try {
                    $replica = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityReplica -ArgumentList $InputObject, $Name
                    $replica.EndpointUrl = $ep.Fqdn
                    $replica.FailoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::$FailoverMode
                    $replica.AvailabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::$AvailabilityMode
                    if ($server.EngineEdition -ne "Standard") {
                        $replica.ConnectionModeInPrimaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInPrimaryRole]::$ConnectionModeInPrimaryRole
                        $replica.ConnectionModeInSecondaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInSecondaryRole]::$ConnectionModeInSecondaryRole
                    }
                    $replica.BackupPriority = $BackupPriority

                    if ($ReadonlyRoutingConnectionUrl) {
                        $replica.ReadonlyRoutingConnectionUrl = $ReadonlyRoutingConnectionUrl
                    }

                    if ($SeedingMode -and $server.VersionMajor -ge 13) {
                        $replica.SeedingMode = $SeedingMode
                        if ($SeedingMode -eq "Automatic") {
                            $serviceaccount = $server.ServiceAccount.Trim()
                            $saname = ([DbaInstanceParameter]($server.DomainInstanceName)).ComputerName

                            if ($serviceaccount) {
                                if ($serviceaccount.StartsWith("NT ")) {
                                    $serviceaccount = "$saname`$"
                                }
                                if ($serviceaccount.StartsWith("$saname")) {
                                    $serviceaccount = "$saname`$"
                                }
                                if ($serviceaccount.StartsWith(".")) {
                                    $serviceaccount = "$saname`$"
                                }
                            }

                            if (-not $serviceaccount) {
                                $serviceaccount = "$saname`$"
                            }

                            if ($server.HostPlatform -ne "Linux") {
                                if ($Pscmdlet.ShouldProcess($second.Name, "Granting Connect permissions to service accounts: $serviceaccounts")) {
                                    $null = Grant-DbaAgPermission -SqlInstance $server -Type AvailabilityGroup -AvailabilityGroup $InputObject.Name -Login $serviceaccount -Permission CreateAnyDatabase
                                    $null = Grant-DbaAgPermission -SqlInstance $server -Login $serviceaccount -Type Endpoint -Permission Connect
                                }
                            }
                        }
                    }

                    if ($Passthru) {
                        return $replica
                    }

                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'Name', 'Role', 'RollupSynchronizationState', 'AvailabilityMode', 'BackupPriority', 'EndpointUrl', 'SessionTimeout', 'FailoverMode', 'ReadonlyRoutingList'
                    $InputObject.AvailabilityReplicas.Add($replica)
                    $agreplica = $InputObject.AvailabilityReplicas[$Name]
                    if ($InputObject.State -eq 'Existing') {
                        Invoke-Create -Object $replica
                        $null = Join-DbaAvailabilityGroup -SqlInstance $instance -SqlCredential $SqlCredential -AvailabilityGroup $InputObject.Name
                        $agreplica.Alter()
                    }
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name ComputerName -value $agreplica.Parent.ComputerName
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name InstanceName -value $agreplica.Parent.InstanceName
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name SqlInstance -value $agreplica.Parent.SqlInstance
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name AvailabilityGroup -value $agreplica.Parent.Name
                    Add-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name Replica -value $agreplica.Name # backwards compat

                    Select-DefaultView -InputObject $agreplica -Property $defaults
                } catch {
                    $msg = $_.Exception.InnerException.InnerException.Message
                    if (-not $msg) {
                        $msg = $_
                    }
                    Stop-Function -Message $msg -ErrorRecord $_ -Continue
                }
            }
        }
    }
}