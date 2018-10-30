#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Set-DbaAgReplica {
    <#
    .SYNOPSIS
        Sets the properties for a replica to an availability group on a SQL Server instance.

    .DESCRIPTION
        Sets the properties for a replica to an availability group on a SQL Server instance.

        Automatically creates a database mirroring endpoint if required.

   .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the SqlInstance instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER AvailabilityGroup
        The Availability Group to which a replica will be bestowed upon.

    .PARAMETER AvailabilityMode
        Sets the availability mode of the availability group replica. Options are: AsynchronousCommit and SynchronousCommit. SynchronousCommit is default.

    .PARAMETER FailoverMode
        Sets the failover mode of the availability group replica. Options are Automatic and Manual.

    .PARAMETER BackupPriority
        Sets the backup priority availability group replica. Default is 50.

    .PARAMETER Endpoint
        By default, this command will attempt to find a DatabaseMirror endpoint. If one does not exist, it will create it.

        If an endpoint must be created, the name "hadr_endpoint" will be used. If an alternative is preferred, use Endpoint.

     .PARAMETER InputObject
        Enables piping from Get-DbaAgReplica.

    .PARAMETER ConnectionModeInPrimaryRole
        Specifies the connection intent modes of an Availability Replica in primary role.

    .PARAMETER ConnectionModeInSecondaryRole
        Specifies the connection modes of an Availability Replica in secondary role.

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
        https://dbatools.io/Set-DbaAgReplica

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup SharePoint | Set-DbaAgReplica -SqlInstance sql2017b

        Sets the properties for sql2017b to the SharePoint availability group on sql2017a

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017a -AvailabilityGroup SharePoint | Set-DbaAgReplica -SqlInstance sql2017b -FailoverMode Manual

        Sets the properties for sql2017b to the SharePoint availability group on sql2017a with a manual failover mode.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$AvailabilityGroup,
        [string]$Name,
        [ValidateSet('AsynchronousCommit', 'SynchronousCommit')]
        [string]$AvailabilityMode,
        [ValidateSet('Automatic', 'Manual', 'External')]
        [string]$FailoverMode,
        [int]$BackupPriority,
        [ValidateSet('AllowAllConnections', 'AllowReadWriteConnections')]
        [string]$ConnectionModeInPrimaryRole,
        [ValidateSet('AllowAllConnections', 'AllowNoConnections', 'AllowReadIntentConnectionsOnly')]
        [string]$ConnectionModeInSecondaryRole,
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode,
        [string]$Endpoint,
        [switch]$Passthru,
        [string]$ReadonlyRoutingConnectionUrl,
        [string]$Certificate,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $AvailabilityGroup -and -not $InputObject) {
            Stop-Function -Message "You must specify either AvailabilityGroup or pipe in an availabilty group to continue."
            return
        }
        
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            if ($AvailabilityGroup) {
                $InputObject = Get-DbaAgReplica -SqlInstance $server -AvailabilityGroup $AvailabilityGroup
            }
            
            if ($Pscmdlet.ShouldProcess($server.Name, "Creating a replica for $($InputObject.Name) named $Name")) {
                try {
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
                    
                    if ($SeedingMode) {
                        $replica.SeedingMode = $SeedingMode
                    }
                    
                    if ($Passthru) {
                        return $replica
                    }
                    
                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'Name', 'Role', 'RollupSynchronizationState', 'AvailabilityMode', 'BackupPriority', 'EndpointUrl', 'SessionTimeout', 'FailoverMode', 'ReadonlyRoutingList'
                    
                    $InputObject.AvailabilityReplicas.Set($replica)
                    $agreplica = $InputObject.AvailabilityReplicas[$Name]
                    Set-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name ComputerName -value $agreplica.Parent.ComputerName
                    Set-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name InstanceName -value $agreplica.Parent.InstanceName
                    Set-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name SqlInstance -value $agreplica.Parent.SqlInstance
                    Set-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name AvailabilityGroup -value $agreplica.Parent.Name
                    Set-Member -Force -InputObject $agreplica -MemberType NoteProperty -Name Replica -value $agreplica.Name # backwards compat
                    
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
