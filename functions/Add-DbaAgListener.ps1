#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Add-DbaAgListener {
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

    .PARAMETER Name
        The name of the listener. If one is not specified, the Availability Group name will be used.

        Note that Name cannot be used with Multiple Ags.

    .PARAMETER IPAddress
        Sets the IP address of the availability group listener.

    .PARAMETER SubnetMask
        Sets the subnet IP mask of the availability group listener. Defaults to 255.255.255.0.

    .PARAMETER Port
        Sets the port number used to communicate with the availability group. Defaults to 1433.

    .PARAMETER Dhcp
        Indicates whether the listener uses DHCP.

    .PARAMETER Passthru
        Don't create the listener, just pass thru an object that can be further customized before creation.

    .PARAMETER InputObject
        Enables piping from Get-DbaAvailabilityGroup

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
        https://dbatools.io/Add-DbaAgListener

    .EXAMPLE
        PS C:\> Add-DbaAgListener -SqlInstance sql2017 -AvailabilityGroup SharePoint -IPAddress 10.0.20.20

        Creates a listener on 10.0.20.20 port 1433 for the SharePoint availability group on sql2017.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017 -AvailabilityGroup availabilitygroup1 | Add-DbaAgListener -Dhcp

        Creates a listener on port 1433 with a dynamic IP for the group1 availability group on sql2017.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [string]$Name,
        [ipaddress]$IPAddress,
        [ipaddress]$SubnetMask = "255.255.255.0",
        [int]$Port = 1433,
        [switch]$Dhcp,
        [switch]$Passthru,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup)) {
            Stop-Function -Message "You must specify one or more databases and one or more Availability Groups when using the SqlInstance parameter."
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($ag in $InputObject) {
            if ((Test-Bound -Not -ParameterName Name)) {
                $Name = $ag.Name
            }
            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Adding $($IPAddress.IPAddressToString) to $($ag.Name)")) {
                try {
                    $aglistener = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener -ArgumentList $ag, $Name
                    $aglistener.PortNumber = $Port
                    $listenerip = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListenerIPAddress -ArgumentList $aglistener

                    if (Test-Bound -ParameterName IPAddress) {
                        $listenerip.IPAddress = $IPAddress.IPAddressToString
                        $listenerip.SubnetMask = $SubnetMask.IPAddressToString
                    }

                    $listenerip.IsDHCP = $Dhcp
                    $aglistener.AvailabilityGroupListenerIPAddresses.Add($listenerip)

                    if ($Passthru) {
                        return $aglistener
                    } else {
                        # something is up with .net create(), force a stop
                        Invoke-Create -Object $aglistener
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }
                Get-DbaAgListener -SqlInstance $ag.Parent -AvailabilityGroup $ag.Name -Listener $Name
            }
        }
    }
}