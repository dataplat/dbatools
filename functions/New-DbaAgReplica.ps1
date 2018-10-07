#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function New-DbaAgReplica {
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
        https://dbatools.io/New-DbaAgReplica
        
    .EXAMPLE
        New-DbaAgReplica -SqlInstance sql2017 -AvailabilityGroup SharePoint
        
        Creates a listener with no IP address. Does not prompt for confirmation.
        
    .EXAMPLE
        Get-AvailabilityGroup -SqlInstance sql2017 -AvailabilityGroup availability group1 | New-DbaAgReplica
        
        Adds the availability groups returned from the Get-AvailabilityGroup function. Prompts for confirmation.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [ValidateSet('AsynchronousCommit', 'SynchronousCommit')]
        [string]$AvailabilityMode,
        [ValidateSet('Automatic', 'Manual')]
        [string]$FailoverMode,
        [string]$Endpoint,
        [switch]$Passthru,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance)) {
            if ((Test-Bound -Not -ParameterName Database) -or (Test-Bound -Not -ParameterName AvailabilityGroup)) {
                Stop-Function -Message "You must specify one or more databases and one or more Availability Groups when using the SqlInstance parameter."
                return
            }
        }
        
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $instance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }
        
        foreach ($ag in $InputObject) {
            if ($Pscmdlet.ShouldProcess("$instance", "Adding availability group $ag to $($ag.Parent.Name)")) {
                try {
                    $replica = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityReplica($AvailabilityGroup, $SqlServerPrimName)
                    $replica.EndpointUrl = "TCP://$($SqlServerPrim.NetName):$($EndpointPrim.Protocol.Tcp.ListenerPort)"
                    $replica.FailoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::$FailoverMode
                    $replica.AvailabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::$AvailabilityMode

                    if ($Passthru) {
                        $replica
                    }
                    else {
                        $ag.AvailabilityReplicas.Add($replica)
                    }
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}