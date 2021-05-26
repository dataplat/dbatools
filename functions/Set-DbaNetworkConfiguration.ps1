function Set-DbaNetworkConfiguration {
    <#
    .SYNOPSIS
        Sets the network configuration of a SQL Server instance.

    .DESCRIPTION
        Sets the network configuration of a SQL Server instance. Needs an object with the structure that Get-DbaNetworkConfiguration returns.

        Remote SQL WMI is used by default. If this doesn't work, then remoting is used.

    .PARAMETER InputObject
        The object with the structure that Get-DbaNetworkConfiguration returns.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SQLWMI
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaNetworkConfiguration

    .EXAMPLE
        PS C:\> Get-DbaNetworkConfiguration -SqlInstance sqlserver2014a

        Returns the network configuration for the default instance on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaNetworkConfiguration -SqlInstance winserver\sqlexpress, sql2016

        Returns the network configuration for the sqlexpress on winserver and the default instance on sql2016.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$InputObject,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    begin {
        $wmiScriptBlock = {
            $instance = $args[0]
            $changes = @()

            $wmiServerProtocols = $wmi.ServerInstances.Where( { $_.Name -eq $instance.InstanceName } ).ServerProtocols

            if ($wmiServerProtocols.Where( { $_.Name -eq 'Sm' } ).IsEnabled -ne $instance.SharedMemoryEnabled) {
                $wmiServerProtocols.Where( { $_.Name -eq 'Sm' } )[0].IsEnabled = $instance.SharedMemoryEnabled
                $wmiServerProtocols.Where( { $_.Name -eq 'Sm' } )[0].Alter()
                $changes += "Changed SharedMemoryEnabled to $($instance.SharedMemoryEnabled)"
            }

            if ($wmiServerProtocols.Where( { $_.Name -eq 'Np' } ).IsEnabled -ne $instance.NamedPipesEnabled) {
                $wmiServerProtocols.Where( { $_.Name -eq 'Np' } )[0].IsEnabled = $instance.NamedPipesEnabled
                $wmiServerProtocols.Where( { $_.Name -eq 'Np' } )[0].Alter()
                $changes += "Changed NamedPipesEnabled to $($instance.NamedPipesEnabled)"
            }

            if ($wmiServerProtocols.Where( { $_.Name -eq 'Tcp' } ).IsEnabled -ne $instance.TCPIPEnabled) {
                $wmiServerProtocols.Where( { $_.Name -eq 'Tcp' } )[0].IsEnabled = $instance.TCPIPEnabled
                $wmiServerProtocols.Where( { $_.Name -eq 'Tcp' } )[0].Alter()
                $changes += "Changed TCPIPEnabled to $($instance.TCPIPEnabled)"
            }

            $wmiTcpIp = $wmiServerProtocols.Where( { $_.Name -eq 'Tcp' } )[0]

            if ($wmiTcpIp.ProtocolProperties.Where( { $_.Name -eq 'Enabled' } ).Value -ne $instance.TCPIPProtokoll.Enabled) {
                $wmiTcpIp.ProtocolProperties.Where( { $_.Name -eq 'Enabled' } )[0].Value = $instance.TCPIPProtokoll.Enabled
                $wmiTcpIp.Alter()
                $changes += "Changed TCPIPProtokoll.Enabled to $($instance.TCPIPProtokoll.Enabled)"
            }

            if ($wmiTcpIp.ProtocolProperties.Where( { $_.Name -eq 'KeepAlive' } ).Value -ne $instance.TCPIPProtokoll.KeepAlive) {
                $wmiTcpIp.ProtocolProperties.Where( { $_.Name -eq 'KeepAlive' } )[0].Value = $instance.TCPIPProtokoll.KeepAlive
                $wmiTcpIp.Alter()
                $changes += "Changed TCPIPProtokoll.KeepAlive to $($instance.TCPIPProtokoll.KeepAlive)"
            }

            if ($wmiTcpIp.ProtocolProperties.Where( { $_.Name -eq 'ListenOnAllIPs' } ).Value -ne $instance.TCPIPProtokoll.ListenAll) {
                $wmiTcpIp.ProtocolProperties.Where( { $_.Name -eq 'ListenOnAllIPs' } )[0].Value = $instance.TCPIPProtokoll.ListenAll
                $wmiTcpIp.Alter()
                $changes += "Changed TCPIPProtokoll.ListenAll to $($instance.TCPIPProtokoll.ListenAll)"
            }

            foreach ($ip in $wmiTcpIp.IPAddresses.Where( { $_.Name -ne 'IPAll' } )) {
                $ipTarget = $instance.TCPIPIPAddresses.Where( { $_.Name -eq $ip.Name } )

                if ($ip.IPAddressProperties.Where( { $_.Name -eq 'Active' } ).Value -ne $ipTarget.Active) {
                    $ip.IPAddressProperties.Where( { $_.Name -eq 'Active' } )[0].Value = $ipTarget.Active
                    $wmiTcpIp.Alter()
                    $changes += "Changed Active for $($ip.Name) to $($ipTarget.Active)"
                }

                if ($ip.IPAddressProperties.Where( { $_.Name -eq 'Enabled' } ).Value -ne $ipTarget.Enabled) {
                    $ip.IPAddressProperties.Where( { $_.Name -eq 'Enabled' } )[0].Value = $ipTarget.Enabled
                    $wmiTcpIp.Alter()
                    $changes += "Changed Enabled for $($ip.Name) to $($ipTarget.Enabled)"
                }

                if ($ip.IPAddressProperties.Where( { $_.Name -eq 'IpAddress' } ).Value -ne $ipTarget.IpAddress) {
                    $ip.IPAddressProperties.Where( { $_.Name -eq 'IpAddress' } )[0].Value = $ipTarget.IpAddress
                    $wmiTcpIp.Alter()
                    $changes += "Changed IpAddress for $($ip.Name) to $($ipTarget.IpAddress)"
                }

                if ($ip.IPAddressProperties.Where( { $_.Name -eq 'TcpDynamicPorts' } ).Value -ne $ipTarget.TcpDynamicPorts) {
                    $ip.IPAddressProperties.Where( { $_.Name -eq 'TcpDynamicPorts' } )[0].Value = $ipTarget.TcpDynamicPorts
                    $wmiTcpIp.Alter()
                    $changes += "Changed TcpDynamicPorts for $($ip.Name) to $($ipTarget.TcpDynamicPorts)"
                }

                if ($ip.IPAddressProperties.Where( { $_.Name -eq 'TcpPort' } ).Value -ne $ipTarget.TcpPort) {
                    $ip.IPAddressProperties.Where( { $_.Name -eq 'TcpPort' } )[0].Value = $ipTarget.TcpPort
                    $wmiTcpIp.Alter()
                    $changes += "Changed TcpPort for $($ip.Name) to $($ipTarget.TcpPort)"
                }
            }

            $ipAll = $wmiTcpIp.IPAddresses.Where( { $_.Name -eq 'IPAll' } )
            $ipTarget = $instance.TCPIPIPAddresses.Where( { $_.Name -eq 'IPAll' } )

            if ($ipAll.IPAddressProperties.Where( { $_.Name -eq 'TcpDynamicPorts' } ).Value -ne $ipTarget.TcpDynamicPorts) {
                $ipAll.IPAddressProperties.Where( { $_.Name -eq 'TcpDynamicPorts' } )[0].Value = $ipTarget.TcpDynamicPorts
                $wmiTcpIp.Alter()
                $changes += "Changed TcpDynamicPorts for $($ipAll.Name) to $($ipTarget.TcpDynamicPorts)"
            }

            if ($ipAll.IPAddressProperties.Where( { $_.Name -eq 'TcpPort' } ).Value -ne $ipTarget.TcpPort) {
                $ipAll.IPAddressProperties.Where( { $_.Name -eq 'TcpPort' } )[0].Value = $ipTarget.TcpPort
                $wmiTcpIp.Alter()
                $changes += "Changed TcpPort for $($ipAll.Name) to $($ipTarget.TcpPort)"
            }

            [PSCustomObject]@{
                ComputerName = $instance.ComputerName
                InstanceName = $instance.InstanceName
                SqlInstance  = $instance.SqlInstance
                Changes      = $changes
            }
        }
    }

    process {
        foreach ($instance in $InputObject) {
            try {
                if ($Pscmdlet.ShouldProcess("Setting network configuration for instance $($instance.InstanceName) on $($instance.ComputerName)")) {
                    Invoke-ManagedComputerCommand -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock $wmiScriptBlock -ArgumentList $instance
                }
            } catch {
                Stop-Function -Message "Setting network configuration for instance $($instance.InstanceName) on $($instance.ComputerName) not possible." -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}
