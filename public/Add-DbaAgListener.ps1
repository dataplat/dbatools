
function Add-DbaAgListener {
    <#
    .SYNOPSIS
        Creates a network listener endpoint for an Availability Group to provide client connectivity

    .DESCRIPTION
        Creates a network listener endpoint that provides a virtual network name and IP address for clients to connect to an Availability Group. The listener automatically routes client connections to the current primary replica, eliminating the need for applications to track which server is currently hosting the primary database.

        This function supports both single-subnet and multi-subnet Availability Group configurations. You can specify static IP addresses for each subnet or use DHCP for automatic IP assignment. For multi-subnet deployments, specify multiple IP addresses and subnet masks to handle failover across geographically dispersed replicas.

        Use this when setting up new Availability Groups or when adding listeners to existing groups that don't have client connectivity configured yet. Without a listener, applications must connect directly to replica server names, which breaks during failover scenarios.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the SqlInstance instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER AvailabilityGroup
        Specifies the name of the Availability Group that will receive the listener. Use this when connecting directly to a SQL Server instance rather than piping from Get-DbaAvailabilityGroup.
        Required when using the SqlInstance parameter to identify which AG on the server needs client connectivity.

    .PARAMETER Name
        Specifies a custom network name for the listener that clients will use to connect. Defaults to the Availability Group name if not specified.
        Use this when you need a different DNS name than your AG name, such as for application connection strings that can't be changed.
        Cannot be used when processing multiple Availability Groups in a single operation.

    .PARAMETER IPAddress
        Specifies one or more static IP addresses for the listener to use across different subnets. Each IP should correspond to a subnet where AG replicas are located.
        Use this for multi-subnet deployments or when DHCP is not available in your network environment.
        Cannot be combined with the Dhcp parameter.

    .PARAMETER SubnetIP
        Specifies the network subnet addresses where the listener IPs will be configured. Auto-calculated from IPAddress and SubnetMask if not provided.
        Use this when you need explicit control over subnet configuration or when auto-calculation produces incorrect results.
        Must match the number of IP addresses specified, or provide a single subnet to apply to all IPs.

    .PARAMETER SubnetMask
        Defines the subnet mask for each listener IP address, controlling the network range. Defaults to 255.255.255.0 (/24).
        Use this when your network uses non-standard subnet sizes or when configuring multi-subnet listeners with different mask requirements.
        Must match the number of IP addresses, or provide a single mask to apply to all IPs.

    .PARAMETER Port
        Specifies the TCP port number that clients will use to connect to the listener. Defaults to 1433.
        Change this when your environment requires non-standard SQL Server ports due to security policies or port conflicts with other services.

    .PARAMETER Dhcp
        Configures the listener to obtain IP addresses automatically from DHCP rather than using static IPs. Simplifies network configuration when DHCP reservations are managed centrally.
        Cannot be used with IPAddress parameter and requires single-subnet AG configurations only.

    .PARAMETER Passthru
        Returns the listener object without creating it on the server, allowing for additional configuration before calling Create().
        Use this when you need to set advanced properties not exposed by this function's parameters before committing the listener to SQL Server.

    .PARAMETER InputObject
        Accepts Availability Group objects from Get-DbaAvailabilityGroup through the pipeline, eliminating the need to specify SqlInstance and AvailabilityGroup parameters.
        Use this approach when working with multiple AGs or when you need to filter AGs before creating listeners.

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
        https://dbatools.io/Add-DbaAgListener

    .EXAMPLE
        PS C:\> Add-DbaAgListener -SqlInstance sql2017 -AvailabilityGroup SharePoint -IPAddress 10.0.20.20

        Creates a listener on 10.0.20.20 port 1433 for the SharePoint availability group on sql2017.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017 -AvailabilityGroup availabilitygroup1 | Add-DbaAgListener -Dhcp

        Creates a listener on port 1433 with a dynamic IP for the group1 availability group on sql2017.

    .EXAMPLE
        PS C:\> Add-DbaAgListener -SqlInstance sql2017 -AvailabilityGroup SharePoint -IPAddress 10.0.20.20,10.1.77.77 -SubnetMask 255.255.252.0

        Creates a multi-subnet listener with 10.0.20.20 and 10.1.77.77, on two /22 subnets, on port 1433 for the SharePoint availability group on sql2017.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [string]$Name,
        [ipaddress[]]$IPAddress,
        [ipaddress[]]$SubnetIP,
        [ipaddress[]]$SubnetMask = "255.255.255.0",
        [int]$Port = 1433,
        [switch]$Dhcp,
        [switch]$Passthru,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup)) {
            Stop-Function -Message "You must specify one or more databases and one or more Availability Groups when using the SqlInstance parameter."
            return
        }

        if ($Dhcp) {
            if (Test-Bound -ParameterName IPAddress) {
                Stop-Function -Message "You cannot specify both an IP address and the Dhcp switch."
                return
            }

            if ($SubnetMask.Count -gt 1 -or $SubnetIP.Count -gt 1) {
                Stop-Function -Message "You can only specify a single subnet when using Dhcp."
                return
            }
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        if (Test-Bound -ParameterName IPAddress) {
            if ($IPAddress.Count -ne $SubnetMask.Count) {
                if ($SubnetMask.Count -eq 1) {
                    # If one subnet mask is supplied, let's assume we want to use the same one for every IP
                    $SubnetMask = $SubnetMask * $IPAddress.Count
                } else {
                    Stop-Function -Message "When specifying multiple IP addresses, the number of subnet masks must match, or give one mask to be used for all IP addresses."
                    return
                }
            }

            if (Test-Bound -Not -ParameterName SubnetIP) {
                # No subnets (subnet IPs) were supplied but we can calculate them with the netmask
                $SubnetIP = for ($ipIndex = 0 ; $ipIndex -lt $IPAddress.Count ; $ipIndex++) {
                    ($IPAddress[$ipIndex].Address -band $SubnetMask[$ipIndex].Address) -as [ipaddress]
                }
            } else {
                if ($IPAddress.Count -ne $SubnetIP.Count) {
                    if ($SubnetIP.Count -eq 1) {
                        # If one subnet IP is supplied, let's assume we want to use the same subnet for every IP
                        $SubnetIP = $SubnetIP * $IPAddress.Count
                    } else {
                        Stop-Function -Message "When specifying subnet IPs explicitly, the number of subnets must match the number of IPs, or use one subnet to be applied to all IPs."
                        return
                    }
                }
            }
        }

        foreach ($ag in $InputObject) {
            if ((Test-Bound -Not -ParameterName Name)) {
                $Name = $ag.Name
            }
            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Adding $($IPAddress.IPAddressToString) to $($ag.Name)")) {
                try {
                    $aglistener = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener -ArgumentList $ag, $Name
                    $aglistener.PortNumber = $Port

                    $ipIndex = 0
                    do {
                        # add the IPs
                        $listenerip = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupListenerIPAddress -ArgumentList $aglistener

                        if (Test-Bound -ParameterName IPAddress) {
                            $listenerip.IPAddress = $IPAddress[$ipIndex]
                        }

                        if ($SubnetIP) {
                            $listenerip.SubnetMask = $SubnetMask[$ipIndex]
                            $listenerip.SubnetIP = $SubnetIP[$ipIndex]
                        }

                        $listenerip.IsDHCP = $Dhcp
                        $aglistener.AvailabilityGroupListenerIPAddresses.Add($listenerip)
                    } while ((++$ipIndex) -lt $IPAddress.Count)

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