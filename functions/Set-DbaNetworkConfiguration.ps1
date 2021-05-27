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

            $wmiServerProtocols = ($wmi.ServerInstances | Where-Object { $_.Name -eq $instance.InstanceName } ).ServerProtocols

            $wmiSpSm = $wmiServerProtocols | Where-Object { $_.Name -eq 'Sm' }
            if ($wmiSpSm.IsEnabled -ne $instance.SharedMemoryEnabled) {
                $wmiSpSm.IsEnabled = $instance.SharedMemoryEnabled
                $wmiSpSm.Alter()
                $changes += "Changed SharedMemoryEnabled to $($instance.SharedMemoryEnabled)"
            }

            $wmiSpNp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Np' }
            if ($wmiSpNp.IsEnabled -ne $instance.NamedPipesEnabled) {
                $wmiSpNp.IsEnabled = $instance.NamedPipesEnabled
                $wmiSpNp.Alter()
                $changes += "Changed NamedPipesEnabled to $($instance.NamedPipesEnabled)"
            }

            $wmiSpTcp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Tcp' }
            if ($wmiSpTcp.IsEnabled -ne $instance.TcpIpEnabled) {
                $wmiSpTcp.IsEnabled = $instance.TcpIpEnabled
                $wmiSpTcp.Alter()
                $changes += "Changed TcpIpEnabled to $($instance.TcpIpEnabled)"
            }

            $wmiSpTcpEnabled = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'Enabled' }
            if ($wmiSpTcpEnabled.Value -ne $instance.TcpIpProperties.Enabled) {
                $wmiSpTcpEnabled.Value = $instance.TcpIpProperties.Enabled
                $wmiSpTcp.Alter()
                $changes += "Changed TcpIpProperties.Enabled to $($instance.TcpIpProperties.Enabled)"
            }

            $wmiSpTcpKeepAlive = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'KeepAlive' }
            if ($wmiSpTcpKeepAlive.Value -ne $instance.TcpIpProperties.KeepAlive) {
                $wmiSpTcpKeepAlive.Value = $instance.TcpIpProperties.KeepAlive
                $wmiSpTcp.Alter()
                $changes += "Changed TcpIpProperties.KeepAlive to $($instance.TcpIpProperties.KeepAlive)"
            }

            $wmiSpTcpListenOnAllIPs = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'ListenOnAllIPs' }
            if ($wmiSpTcpListenOnAllIPs.Value -ne $instance.TcpIpProperties.ListenAll) {
                $wmiSpTcpListenOnAllIPs.Value = $instance.TcpIpProperties.ListenAll
                $wmiSpTcp.Alter()
                $changes += "Changed TcpIpProperties.ListenAll to $($instance.TcpIpProperties.ListenAll)"
            }

            $wmiIPn = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -ne 'IPAll' }
            foreach ($ip in $wmiIPn) {
                $ipTarget = $instance.TcpIpAddresses | Where-Object { $_.Name -eq $ip.Name }

                $ipActive = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'Active' }
                if ($ipActive.Value -ne $ipTarget.Active) {
                    $ipActive.Value = $ipTarget.Active
                    $wmiSpTcp.Alter()
                    $changes += "Changed Active for $($ip.Name) to $($ipTarget.Active)"
                }

                $ipEnabled = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'Enabled' }
                if ($ipEnabled.Value -ne $ipTarget.Enabled) {
                    $ipEnabled.Value = $ipTarget.Enabled
                    $wmiSpTcp.Alter()
                    $changes += "Changed Enabled for $($ip.Name) to $($ipTarget.Enabled)"
                }

                $ipIpAddress = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'IpAddress' }
                if ($ipIpAddress.Value -ne $ipTarget.IpAddress) {
                    $ipIpAddress.Value = $ipTarget.IpAddress
                    $wmiSpTcp.Alter()
                    $changes += "Changed IpAddress for $($ip.Name) to $($ipTarget.IpAddress)"
                }

                $ipTcpDynamicPorts = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' }
                if ($ipTcpDynamicPorts.Value -ne $ipTarget.TcpDynamicPorts) {
                    $ipTcpDynamicPorts.Value = $ipTarget.TcpDynamicPorts
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpDynamicPorts for $($ip.Name) to $($ipTarget.TcpDynamicPorts)"
                }

                $ipTcpPort = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
                if ($ipTcpPort.Value -ne $ipTarget.TcpPort) {
                    $ipTcpPort.Value = $ipTarget.TcpPort
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpPort for $($ip.Name) to $($ipTarget.TcpPort)"
                }
            }

            $wmiIPAll = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -eq 'IPAll' }
            $ipTarget = $instance.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }

            $ipTcpDynamicPorts = $wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' }
            if ($ipTcpDynamicPorts.Value -ne $ipTarget.TcpDynamicPorts) {
                $ipTcpDynamicPorts.Value = $ipTarget.TcpDynamicPorts
                $wmiSpTcp.Alter()
                $changes += "Changed TcpDynamicPorts for $($wmiIPAll.Name) to $($ipTarget.TcpDynamicPorts)"
            }

            $ipTcpPort = $wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
            if ($ipTcpPort.Value -ne $ipTarget.TcpPort) {
                $ipTcpPort.Value = $ipTarget.TcpPort
                $wmiSpTcp.Alter()
                $changes += "Changed TcpPort for $($wmiIPAll.Name) to $($ipTarget.TcpPort)"
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
