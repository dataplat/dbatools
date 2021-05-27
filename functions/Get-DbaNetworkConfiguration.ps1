function Get-DbaNetworkConfiguration {
    <#
    .SYNOPSIS
        Returns the network configuration of a SQL Server instance as shown in the SQL Server Configuration Manager.

    .DESCRIPTION
        Returns a PowerShell object with the network configuration of a SQL Server instance as shown in the SQL Server Configuration Manager.

        Remote SQL WMI is used by default. If this doesn't work, then remoting is used.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

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
        https://dbatools.io/Get-DbaNetworkConfiguration

    .EXAMPLE
        PS C:\> Get-DbaNetworkConfiguration -SqlInstance sqlserver2014a

        Returns the network configuration for the default instance on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaNetworkConfiguration -SqlInstance winserver\sqlexpress, sql2016

        Returns the network configuration for the sqlexpress on winserver and the default instance on sql2016.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    begin {
        $wmiScriptBlock = {
            $instance = $args[0]

            $wmiServerProtocols = ($wmi.ServerInstances | Where-Object { $_.Name -eq $instance.InstanceName } ).ServerProtocols

            $wmiSpSm = $wmiServerProtocols | Where-Object { $_.Name -eq 'Sm' }
            $wmiSpNp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Np' }
            $wmiSpTcp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Tcp' }

            $outputTcpIpProtocol = [PSCustomObject]@{
                Enabled   = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'Enabled' } ).Value
                KeepAlive = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'KeepAlive' } ).Value
                ListenAll = ($wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'ListenOnAllIPs' } ).Value
            }

            $wmiIPn = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -ne 'IPAll' }
            $outputTcpIpIPAddressesIPn = foreach ($ip in $wmiIPn) {
                [PSCustomObject]@{
                    Name            = $ip.Name
                    Active          = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'Active' } ).Value
                    Enabled         = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'Enabled' } ).Value
                    IPAddress       = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'IpAddress' } ).Value
                    TCPDynamicPorts = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' } ).Value
                    TCPPort         = ($ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' } ).Value
                }
            }

            $wmiIPAll = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -eq 'IPAll' }
            $outputTcpIpIPAddressesIPAll = [PSCustomObject]@{
                Name            = $wmiIPAll.Name
                TCPDynamicPorts = ($wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' } ).Value
                TCPPort         = ($wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' } ).Value
            }

            [PSCustomObject]@{
                ComputerName        = $instance.ComputerName
                InstanceName        = $instance.InstanceName
                SqlInstance         = $instance.SqlFullName.Trim('[]')
                SharedMemoryEnabled = $wmiSpSm.IsEnabled
                NamedPipesEnabled   = $wmiSpNp.IsEnabled
                TCPIPEnabled        = $wmiSpTcp.IsEnabled
                TCPIPProtokoll      = $outputTcpIpProtocol
                TCPIPIPAddresses    = $outputTcpIpIPAddressesIPn + $outputTcpIpIPAddressesIPAll
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Invoke-ManagedComputerCommand -ComputerName $instance.ComputerName -Credential $Credential -ScriptBlock $wmiScriptBlock -ArgumentList $instance
            } catch {
                Stop-Function -Message "Connection to $($instance.ComputerName) not possible." -Target $instance -ErrorRecord $_ -Continue
            }
        }
    }
}
