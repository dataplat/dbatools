function Set-DbaTcpPort {
    <#
    .SYNOPSIS
        Changes the TCP port used by the specified SQL Server.

    .DESCRIPTION
        This function changes the TCP port used by the specified SQL Server.

        Be aware that the Database Engine begins listening on a new port only when restarted. So you have to restart the Database Engine that the new settings become effective.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server instance as a different user.

    .PARAMETER Credential
        Credential object used to connect to the Windows server itself as a different user (like SQL Configuration Manager).

    .PARAMETER Port
        TCPPort that SQLService should listen on.

    .PARAMETER IpAddress
        Ip address to which the change should apply, if omitted AllIp (0.0.0.0) will be changed with the new port number.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Will restart SQL Server and SQL Server Agent service to apply the change.

    .NOTES
        Tags: Network, Connection, TCP, Configure
        Author: @H0s0n77

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaTcpPort

    .EXAMPLE
        PS C:\> Set-DbaTcpPort -SqlInstance sql2017 -Port 1433

        Sets the port number 1433 for all IP Addresses on the default instance on sql2017. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Set-DbaTcpPort -SqlInstance winserver\sqlexpress -IpAddress 192.168.1.22 -Port 1433 -Confirm:$false

        Sets the port number 1433 for IP 192.168.1.22 on the sqlexpress instance on winserver. Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Set-DbaTcpPort -SqlInstance sql2017, sql2019 -port 1337 -Credential ad\dba -Force

        Sets the port number 1337 for all IP Addresses on SqlInstance sql2017 and sql2019 using the credentials for ad\dba. Prompts for confirmation. Restarts the service.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,
        [IpAddress[]]$IpAddress,
        [switch]$Force,
        [switch]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if ('0.0.0.0' -eq $IpAddress) {
            $IpAddress = $null
        }

        if ($IpAddress -and $SqlInstance.Count -gt 1) {
            Stop-Function -Message "-IpAddress switch cannot be used with a collection of serveraddresses" -Target $SqlInstance
            return
        }

        foreach ($instance in $SqlInstance) {
            $computerFullName = $instance.ComputerName
            $instanceName = $instance.InstanceName
            if (-not $IpAddress) {
                if ($Pscmdlet.ShouldProcess($instance, "Setting port to $Port for IPAll of $instance")) {
                    Set-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -StaticPortForIPAll $Port -EnableException:$EnableException -Confirm:$false
                }
            } else {
                try {
                    $netConf = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -OutputType Full -EnableException
                } catch {
                    Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                }

                $netConf.TcpIpEnabled = $true
                $netConf.TcpIpProperties.Enabled = $true
                $netConf.TcpIpProperties.ListenAll = $false
                foreach ($ip in $IpAddress) {
                    $ipConf = $netConf.TcpIpAddresses | Where-Object { $_.IpAddress -eq $ip }
                    if ($ipConf) {
                        $ipConf.Enabled = $true
                        $ipConf.TcpDynamicPorts = ''
                        $ipConf.TcpPort = "$Port"  # change if [int[]]: $Port -join ','
                    } else {
                        Write-Message -Level Warning -Message "IP address $ip not found, skipping."
                    }
                }

                if ($Pscmdlet.ShouldProcess($instance, "Setting port to $Port for IP address $IpAddress of $instance")) {
                    $netConf | Set-DbaNetworkConfiguration -Credential $Credential -EnableException:$EnableException -Confirm:$false
                }

                if (Test-Bound -ParameterName Force) {
                    if ($PSCmdlet.ShouldProcess($instance, "Force provided, restarting Engine and Agent service for $instance on $computerFullName")) {
                        try {
                            $null = Restart-DbaService -SqlInstance $instance -Type Engine -Force -EnableException
                        } catch {
                            Stop-Function -Message "Issue restarting $instance on $computerFullName" -Target $instance -Continue -ErrorRecord $_
                        }
                    }
                }
            }
        }
    }
}
