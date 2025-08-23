function Set-DbaTcpPort {
    <#
    .SYNOPSIS
        Configures SQL Server TCP port settings for specified instances and IP addresses.

    .DESCRIPTION
        Configures TCP port settings for SQL Server instances by modifying the network configuration through SQL Server Configuration Manager functionality. This replaces the manual process of opening SQL Server Configuration Manager to change port settings for security hardening or network compliance.

        The function can target all IP addresses (IPAll setting) or specific IP addresses, disables dynamic port allocation, and sets static port numbers. This is commonly used to move SQL Server off the default port 1433 for security purposes, configure custom ports for named instances, or meet organizational network segmentation requirements.

        Important: SQL Server must be restarted before the new port configuration takes effect. Use the -Force parameter to automatically restart the Database Engine service, or restart manually after running the command.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server instance as a different user.

    .PARAMETER Credential
        Credential object used to connect to the Windows server itself as a different user (like SQL Configuration Manager).

    .PARAMETER Port
        Specifies the TCP port number for SQL Server to listen on, replacing any existing static or dynamic port configuration.
        Use this to move SQL Server off the default port 1433 for security hardening or to configure custom ports for named instances.
        Accepts any valid port number between 1 and 65535, with common choices being 1433 (default), 1434, or organization-specific port ranges.

    .PARAMETER IpAddress
        Specifies which IP address should listen on the configured port instead of applying to all IP addresses.
        Use this for multi-homed servers where you need SQL Server to listen only on specific network interfaces.
        When omitted, the port change applies to all IP addresses (IPAll setting), which is the typical configuration for most servers.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Automatically restarts the SQL Server Database Engine service to apply the new port configuration immediately.
        Use this when you need the port change to take effect right away instead of waiting for the next service restart.
        Without this parameter, you must manually restart SQL Server before the new port settings become active.

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
        [int[]]$Port,
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
                if ($Pscmdlet.ShouldProcess($instance, "Setting port to $($Port -join ',') for IPAll of $instance")) {
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
                        $ipConf.TcpPort = $Port -join ','
                    } else {
                        Write-Message -Level Warning -Message "IP address $ip not found, skipping."
                    }
                }

                if ($Pscmdlet.ShouldProcess($instance, "Setting port to $($Port -join ',') for IP address $IpAddress of $instance")) {
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