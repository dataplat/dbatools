#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Add-DbaAgReplica {
<#
    .SYNOPSIS
        Adds a replica to an availability group on a SQL Server instance.
        
    .DESCRIPTION
        Adds a replica to an availability group on a SQL Server instance.
    
    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.
        
    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)
        
    .PARAMETER AvailabilityGroup
        The Availability Group to which a listener will be bestowed upon.
    
    .PARAMETER AvailabilityMode
        Sets the IP address of the availability group listener.
    
    .PARAMETER FailoverMode
        Sets the subnet IP mask of the availability group listener.
    
    .PARAMETER Endpoint
        Sets the number of the port used to communicate with the availability group.
    
    .PARAMETER Passthru
        Don't create the listener, just pass thru an object that can be further customized before creation.
    
    .PARAMETER InputObject
        Internal parameter to support piping from Get-DbaDatabase.

    .PARAMETER ConnectionModeInPrimaryRole
        Specifies the connection intent modes of an Availability Replica in primary role. AllowAllConnections by default.
    
    .PARAMETER ConnectionModeInSecondaryRole
        Specifies the connection modes of an Availability Replica in secondary role. AllowAllConnections by default.
    
    .PARAMETER ReadonlyRoutingConnectionUrl
        Sets the read only routing connection url for the availability replica.
    
    .PARAMETER SeedingMode
        Specifies how the secondary replica will be initially seeded.
    
        Automatic. Enables direct seeding. This method will seed the secondary replica over the network. This method does not require you to backup and restore a copy of the primary database on the replica.
        
        Manual. Specifies manual seeding. This method requires you to create a backup of the database on the primary replica and manually restore that backup on the secondary replica.
    
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
        PS C:\> Add-DbaAgReplica -SqlInstance sql2017 -AvailabilityGroup SharePoint
        
        Creates a listener with no IP address. Does not prompt for confirmation.
        
    .EXAMPLE
        PS C:\> Get-AvailabilityGroup -SqlInstance sql2017 -AvailabilityGroup availability group1 | Add-DbaAgReplica
        
        Adds the availability groups returned from the Get-AvailabilityGroup function. Prompts for confirmation.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [string]$Name,
        [ValidateSet('AsynchronousCommit', 'SynchronousCommit')]
        [string]$AvailabilityMode = "SynchronousCommit",
        [ValidateSet('Automatic', 'Manual')]
        [string]$FailoverMode = "Automatic",
        [int]$BackupPriority = 50,
        [ValidateSet('AllowAllConnections', 'AllowReadWriteConnections')]
        [string]$ConnectionModeInPrimaryRole = 'AllowAllConnections',
        [ValidateSet('AllowAllConnections', 'AllowNoConnections', 'AllowReadIntentConnectionsOnly')]
        [string]$ConnectionModeInSecondaryRole = 'AllowAllConnections',
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode = 'Automatic',
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
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            
            if ($Certificate) {
                $cert = Get-DbaDbCertificate -SqlInstance $server -Certificate $Certificate
                if (-not $cert) {
                    Stop-Function -Message "Certificate $Certificate does not exist on $instance" -ErrorRecord $_ -Target $Certificate -Continue
                }
            }
            
            if ($AvailabilityGroup) {
                $InputObject = Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $AvailabilityGroup
            }
            
            $ep = Get-DbaEndpoint -SqlInstance $server -Endpoint $Endpoint -Type DatabaseMirroring
            
            if (-not $ep) {
                if ($Pscmdlet.ShouldProcess("$instance", "Creating an endpoint")) {
                    Write-Message -Level Verbose -Message "Adding endpoint named AvailabilityGroup to $instance"
                    $ep = New-DbaEndpoint -SqlInstance $server -Name hadr_endpoint -Type DatabaseMirroring -EndpointEncryption Supported -EncryptionAlgorithm Aes -Certificate $Certificate
                    $null = $ep | Start-DbaEndpoint
                }
            }
            
            if ($Pscmdlet.ShouldProcess("$instance", "Creating a replica")) {
                try {
                    $replica = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityReplica -ArgumentList $InputObject, $server.Name
                    $replica.EndpointUrl = $ep.Fqdn
                    $replica.FailoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::$FailoverMode
                    $replica.AvailabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::$AvailabilityMode
                    $replica.ConnectionModeInPrimaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInPrimaryRole]::$ConnectionModeInPrimaryRole
                    $replica.ConnectionModeInSecondaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInSecondaryRole]::$ConnectionModeInSecondaryRole
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
                    
                    $InputObject.AvailabilityReplicas.Add($replica)
                }
                catch {
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