#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function New-DbaAgListener {
<#
    .SYNOPSIS
        Adds a listener to an availability group on a SQL Server instance.
        
    .DESCRIPTION
        Adds a listener to an availability group on a SQL Server instance.
    
   .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the SqlInstance instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER AvailabilityGroup
        The Availability Group to which a listener will be bestowed upon.
    
    .PARAMETER IPAddress
        Sets the IP address of the availability group listener.
    
    .PARAMETER SubnetMask
        Sets the subnet IP mask of the availability group listener.
    
    .PARAMETER Port
        Sets the number of the port used to communicate with the availability group.
    
    .PARAMETER Dhcp
        Indicates whether the object is DHCP.
    
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
        https://dbatools.io/New-DbaAgListener
        
    .EXAMPLE
        PS C:\> New-DbaAgListener -SqlInstance sql2017 -AvailabilityGroup SharePoint
        
        Creates a listener with no IP address. Does not prompt for confirmation.
        
    .EXAMPLE
        PS C:\> Get-AvailabilityGroup -SqlInstance sql2017 -AvailabilityGroup availability group1 | New-DbaAgListener
        
        Adds the availability groups returned from the Get-AvailabilityGroup function. Prompts for confirmation.

#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [ipaddress[]]$IPAddress,
        [ipaddress]$SubnetMask = "255.255.255.0",
        [int]$Port = 1433,
        [switch]$Dhcp,
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
        
        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }
        
        foreach ($ag in $InputObject) {
            if ((Test-Bound -Not -ParameterName Name)) {
                $Name = $ag.Name
            }
            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Adding $IPAddress to $ag")) {
                try {
                    $aglistener = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener -ArgumentList $ag, $Name
                    $aglistener.PortNumber = $Port
                    
                    foreach ($ip in $IPAddress.IPAddressToString) {
                        $listenerip = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListenerIPAddress -ArgumentList $aglistener
                        $listenerip.IPAddress = $ip
                        $listenerip.SubnetMask = $SubnetMask.IPAddressToString
                        $listenerip.IsDHCP = $Dhcp
                        $aglistener.AvailabilityGroupListenerIPAddresses.Add($listenerip)
                    }
                    
                    if ($Passthru) {
                        return $aglistener
                    }
                    else {
                        $aglistener.Create()
                    }
                    
                    Get-DbaAgListener -SqlInstance $ag.Parent -AvailabilityGroup $ag.Name -Listener $Name
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