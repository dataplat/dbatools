function Get-DbaNetworkConfiguration {
    <#
    .SYNOPSIS
        Returns the network configuration of a SQL Server instance as shown in the SQL Server Configuration Manager.

    .DESCRIPTION
        Returns a PowerShell object with the network configuration of a SQL Server instance as shown in the SQL Server Configuration Manager.

        Remote SQL WMI is used by default. If this doesn't work, then remoting is used.

        For a detailed explenation of the different properties see the documentation at:
        https://docs.microsoft.com/en-us/sql/tools/configuration-manager/sql-server-network-configuration

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER OutputType
        Defines what information is returned from the command.
        Options include: Full, ServerProtocols, TcpIpProperties or TcpIpAddresses. Full by default.

        Full returns one object per SqlInstance with information about the server protocols
        and nested objects with information about TCP/IP properties and TCP/IP addresses.

        ServerProtocols returns one object per SqlInstance with information about the server protocols only.

        TcpIpProperties returns one object per SqlInstance with information about the TCP/IP protocol properties only.

        TcpIpAddresses returns one object per SqlInstance and IP address.
        If the instance listens on all IP addresses (TcpIpProperties.ListenAll), only the information about the IPAll address is returned.
        Otherwise only information about the individual IP addresses is returned.
        For more details see: https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/configure-a-server-to-listen-on-a-specific-tcp-port

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
        https://dbatools.io/Get-DbaNetworkConfiguration

    .EXAMPLE
        PS C:\> Get-DbaNetworkConfiguration -SqlInstance sqlserver2014a

        Returns the network configuration for the default instance on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaNetworkConfiguration -SqlInstance winserver\sqlexpress, sql2016 -OutputType ServerProtocols

        Returns information about the server protocols for the sqlexpress on winserver and the default instance on sql2016.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [ValidateSet('Full', 'ServerProtocols', 'TcpIpProperties', 'TcpIpAddresses')]
        [string]$OutputType = 'Full',
        [switch]$EnableException
    )

    begin {
        $wmiScriptBlock = {
            $instance = $args[0]

            $wmiServerProtocols = ($wmi.ServerInstances | Where-Object { $_.Name -eq $instance.InstanceName } ).ServerProtocols

            $wmiSpSm = $wmiServerProtocols | Where-Object { $_.Name -eq 'Sm' }
            $wmiSpNp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Np' }
            $wmiSpTcp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Tcp' }

            $outputTcpIpProperties = [PSCustomObject]@{
                Enabled   = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'Enabled' } ).Value
                KeepAlive = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'KeepAlive' } ).Value
                ListenAll = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'ListenOnAllIPs' } ).Value
            }

            $wmiIPn = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -ne 'IPAll' }
            $outputTcpIpAddressesIPn = foreach ($ip in $wmiIPn) {
                [PSCustomObject]@{
                    Name            = $ip.Name
                    Active          = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'Active' } ).Value
                    Enabled         = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'Enabled' } ).Value
                    IpAddress       = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'IpAddress' } ).Value
                    TcpDynamicPorts = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' } ).Value
                    TcpPort         = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' } ).Value
                }
            }

            $wmiIPAll = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -eq 'IPAll' }
            $outputTcpIpAddressesIPAll = [PSCustomObject]@{
                Name            = $wmiIPAll.Name
                TcpDynamicPorts = ($wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' } ).Value
                TcpPort         = ($wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' } ).Value
            }

            [PSCustomObject]@{
                ComputerName        = $instance.ComputerName
                InstanceName        = $instance.InstanceName
                SqlInstance         = $instance.SqlFullName.Trim('[]')
                SharedMemoryEnabled = $wmiSpSm.IsEnabled
                NamedPipesEnabled   = $wmiSpNp.IsEnabled
                TcpIpEnabled        = $wmiSpTcp.IsEnabled
                TcpIpProperties     = $outputTcpIpProperties
                TcpIpAddresses      = $outputTcpIpAddressesIPn + $outputTcpIpAddressesIPAll
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $netConf = Invoke-ManagedComputerCommand -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock $wmiScriptBlock -ArgumentList $instance

                if ($OutputType -eq 'Full') {
                    $netConf
                } elseif ($OutputType -eq 'ServerProtocols') {
                    [PSCustomObject]@{
                        ComputerName        = $netConf.ComputerName
                        InstanceName        = $netConf.InstanceName
                        SqlInstance         = $netConf.SqlInstance
                        SharedMemoryEnabled = $netConf.SharedMemoryEnabled
                        NamedPipesEnabled   = $netConf.NamedPipesEnabled
                        TcpIpEnabled        = $netConf.TcpIpEnabled
                    }
                } elseif ($OutputType -eq 'TcpIpProperties') {
                    [PSCustomObject]@{
                        ComputerName = $netConf.ComputerName
                        InstanceName = $netConf.InstanceName
                        SqlInstance  = $netConf.SqlInstance
                        Enabled      = $netConf.TcpIpProperties.Enabled
                        KeepAlive    = $netConf.TcpIpProperties.KeepAlive
                        ListenAll    = $netConf.TcpIpProperties.ListenAll
                    }
                } elseif ($OutputType -eq 'TcpIpAddresses') {
                    if ($netConf.TcpIpProperties.ListenAll) {
                        $ipConf = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                        [PSCustomObject]@{
                            ComputerName    = $netConf.ComputerName
                            InstanceName    = $netConf.InstanceName
                            SqlInstance     = $netConf.SqlInstance
                            Name            = $ipConf.Name
                            TcpDynamicPorts = $ipConf.TcpDynamicPorts
                            TcpPort         = $ipConf.TcpPort
                        }
                    } else {
                        $ipConf = $netConf.TcpIpAddresses | Where-Object { $_.Name -ne 'IPAll' }
                        foreach ($ip in $ipConf) {
                            [PSCustomObject]@{
                                ComputerName    = $netConf.ComputerName
                                InstanceName    = $netConf.InstanceName
                                SqlInstance     = $netConf.SqlInstance
                                Name            = $ip.Name
                                Active          = $ip.Active
                                Enabled         = $ip.Enabled
                                IpAddress       = $ip.IpAddress
                                TcpDynamicPorts = $ip.TcpDynamicPorts
                                TcpPort         = $ip.TcpPort
                            }
                        }
                    }
                }
            } catch {
                Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}
