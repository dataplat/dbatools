function Set-DbaNetworkConfiguration {
    <#
    .SYNOPSIS
        Sets the network configuration of a SQL Server instance.

    .DESCRIPTION
        Sets the network configuration of a SQL Server instance.

        Parameters are available for typical tasks like enabling or disabling a protokoll or switching between dynamic and static ports.
        To be more flexible, you can use Get-DbaNetworkConfiguration to get an object that represents the complete network configuration
        like you would see it with the SQL Server Configuration Manager.
        You can change any setting of this object and then pass it to Set-DbaNetworkConfiguration via pipeline or InputObject parameter.

        Every change to the network configuration needs a service restart to take effect. To do this, use the RestartService parameter.

        Remote SQL WMI is used by default. If this doesn't work, then remoting is used.

        For a detailed explenation of the different properties see the documentation at:
        https://docs.microsoft.com/en-us/sql/tools/configuration-manager/sql-server-network-configuration

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER EnableProtokoll
        Enables one of the following network protokolls: SharedMemory, NamedPipes, TcpIp.

    .PARAMETER DisableProtokoll
        Disables one of the following network protokolls: SharedMemory, NamedPipes, TcpIp.

    .PARAMETER DynamicPortForIPAll
        Configures the instance to listen on a dynamic port for all IP addresses.
        Will enable the TCP/IP protokoll if needed.
        Will set TcpIpProperties.ListenAll to $true if needed.
        Will reset the last used dynamic port if already set.

    .PARAMETER StaticPortForIPAll
        Configures the instance to listen on one or more static ports for all IP addresses.
        Will enable the TCP/IP protokoll if needed.
        Will set TcpIpProperties.ListenAll to $true if needed.

    .PARAMETER RestartService
        Every change to the network configuration needs a service restart to take effect.
        This switch will force a restart of the service if the network configuration has changed.

    .PARAMETER InputObject
        The object with the structure that Get-DbaNetworkConfiguration returns.
        Get-DbaNetworkConfiguration has be run with the default OutputType Full to get the complete object.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: SQLWMI
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaNetworkConfiguration

    .EXAMPLE
        PS C:\> Set-DbaNetworkConfiguration -SqlInstance sql2016 -EnableProtokoll SharedMemory -RestartService

        Ensures that the shared memory network protokoll for the default instance on sql2016 is enabled.
        Restarts the service if needed.

    .EXAMPLE
        PS C:\> Set-DbaNetworkConfiguration -SqlInstance sql2016\test -StaticPortForIPAll 14331, 14332 -RestartService

        Ensures that the TCP/IP network protokoll is enabled and configured to use the ports 14331 and 14332 for all IP addresses.
        Restarts the service if needed.

    .EXAMPLE
        PS C:\> $netConf = Get-DbaNetworkConfiguration -SqlInstance sqlserver2014a
        PS C:\> $netConf.TcpIpProperties.KeepAlive = 60000
        PS C:\> $netConf | Set-DbaNetworkConfiguration -RestartService -Confirm:$false

        Changes the value of the KeepAlive property for the default instance on sqlserver2014a and restarts the service.
        Does not prompt for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High", DefaultParameterSetName = 'NonPipeline')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateSet('SharedMemory', 'NamedPipes', 'TcpIp')]
        [string]$EnableProtokoll,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateSet('SharedMemory', 'NamedPipes', 'TcpIp')]
        [string]$DisableProtokoll,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [switch]$DynamicPortForIPAll,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [int[]]$StaticPortForIPAll,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$RestartService,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [object[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $wmiScriptBlock = {
            $targetConf = $args[0]
            $changes = @()

            $wmiServerProtocols = ($wmi.ServerInstances | Where-Object { $_.Name -eq $targetConf.InstanceName } ).ServerProtocols

            $wmiSpSm = $wmiServerProtocols | Where-Object { $_.Name -eq 'Sm' }
            if ($wmiSpSm.IsEnabled -ne $targetConf.SharedMemoryEnabled) {
                $wmiSpSm.IsEnabled = $targetConf.SharedMemoryEnabled
                $wmiSpSm.Alter()
                $changes += "Changed SharedMemoryEnabled to $($targetConf.SharedMemoryEnabled)"
            }

            $wmiSpNp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Np' }
            if ($wmiSpNp.IsEnabled -ne $targetConf.NamedPipesEnabled) {
                $wmiSpNp.IsEnabled = $targetConf.NamedPipesEnabled
                $wmiSpNp.Alter()
                $changes += "Changed NamedPipesEnabled to $($targetConf.NamedPipesEnabled)"
            }

            $wmiSpTcp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Tcp' }
            if ($wmiSpTcp.IsEnabled -ne $targetConf.TcpIpEnabled) {
                $wmiSpTcp.IsEnabled = $targetConf.TcpIpEnabled
                $wmiSpTcp.Alter()
                $changes += "Changed TcpIpEnabled to $($targetConf.TcpIpEnabled)"
            }

            $wmiSpTcpEnabled = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'Enabled' }
            if ($wmiSpTcpEnabled.Value -ne $targetConf.TcpIpProperties.Enabled) {
                $wmiSpTcpEnabled.Value = $targetConf.TcpIpProperties.Enabled
                $wmiSpTcp.Alter()
                $changes += "Changed TcpIpProperties.Enabled to $($targetConf.TcpIpProperties.Enabled)"
            }

            $wmiSpTcpKeepAlive = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'KeepAlive' }
            if ($wmiSpTcpKeepAlive.Value -ne $targetConf.TcpIpProperties.KeepAlive) {
                $wmiSpTcpKeepAlive.Value = $targetConf.TcpIpProperties.KeepAlive
                $wmiSpTcp.Alter()
                $changes += "Changed TcpIpProperties.KeepAlive to $($targetConf.TcpIpProperties.KeepAlive)"
            }

            $wmiSpTcpListenOnAllIPs = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'ListenOnAllIPs' }
            if ($wmiSpTcpListenOnAllIPs.Value -ne $targetConf.TcpIpProperties.ListenAll) {
                $wmiSpTcpListenOnAllIPs.Value = $targetConf.TcpIpProperties.ListenAll
                $wmiSpTcp.Alter()
                $changes += "Changed TcpIpProperties.ListenAll to $($targetConf.TcpIpProperties.ListenAll)"
            }

            $wmiIPn = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -ne 'IPAll' }
            foreach ($ip in $wmiIPn) {
                $ipTarget = $targetConf.TcpIpAddresses | Where-Object { $_.Name -eq $ip.Name }

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
            $ipTarget = $targetConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }

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

            $changes
        }
    }

    process {
        if ($SqlInstance -and (Test-Bound -Not -ParameterName EnableProtokoll, DisableProtokoll, DynamicPortForIPAll, StaticPortForIPAll)) {
            Stop-Function -Message "You must choose an action if SqlInstance is used."
            return
        }

        if ($SqlInstance -and (Test-Bound -ParameterName EnableProtokoll, DisableProtokoll, DynamicPortForIPAll, StaticPortForIPAll -Not -Max 1)) {
            Stop-Function -Message "Only one action is allowed at a time."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Get network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)."
                $netConf = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -EnableException
            } catch {
                Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
            }

            if ($EnableProtokoll) {
                if ($netConf."${EnableProtokoll}Enabled") {
                    Write-Message -Level Verbose -Message "Protokoll $EnableProtokoll is already enabled on $instance."
                } else {
                    Write-Message -Level Verbose -Message "Will enable protokoll $EnableProtokoll on $instance."
                    $netConf."${EnableProtokoll}Enabled" = $true
                    if ($EnableProtokoll -eq 'TcpIp') {
                        $netConf.TcpIpProperties.Enabled = $true
                    }
                }
            }

            if ($DisableProtokoll) {
                if ($netConf."${DisableProtokoll}Enabled") {
                    Write-Message -Level Verbose -Message "Will disable protokoll $EnableProtokoll on $instance."
                    $netConf."${DisableProtokoll}Enabled" = $false
                    if ($DisableProtokoll -eq 'TcpIp') {
                        $netConf.TcpIpProperties.Enabled = $false
                    }
                } else {
                    Write-Message -Level Verbose -Message "Protokoll $EnableProtokoll is already disabled on $instance."
                }
            }

            if ($DynamicPortForIPAll) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protokoll TcpIp on $instance."
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protokoll TcpIp to True on $instance."
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if (-not $netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protokoll TcpIp to True on $instance."
                    $netConf.TcpIpProperties.ListenAll = $true
                }
                $ipAll = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IPAll to '0' on $instance."
                $ipAll.TcpDynamicPorts = '0'
                Write-Message -Level Verbose -Message "Will set property TcpPort of IPAll to '' on $instance."
                $ipAll.TcpPort = ''
            }

            if ($StaticPortForIPAll) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protokoll TcpIp on $instance."
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protokoll TcpIp to True on $instance."
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if (-not $netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protokoll TcpIp to True on $instance."
                    $netConf.TcpIpProperties.ListenAll = $true
                }
                $ipAll = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IPAll to '' on $instance."
                $ipAll.TcpDynamicPorts = ''
                $port = $StaticPortForIPAll -join ','
                Write-Message -Level Verbose -Message "Will set property TcpPort of IPAll to '$port' on $instance."
                $ipAll.TcpPort = $port
            }

            $InputObject += $netConf
        }

        foreach ($netConf in $InputObject) {
            try {
                $output = [PSCustomObject]@{
                    ComputerName  = $netConf.ComputerName
                    InstanceName  = $netConf.InstanceName
                    SqlInstance   = $netConf.SqlInstance
                    Changes       = $null
                    RestartNeeded = $false
                    Restarted     = $false
                }

                if ($Pscmdlet.ShouldProcess("Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName)")) {
                    $output.Changes = Invoke-ManagedComputerCommand -ComputerName $netConf.ComputerName -Credential $Credential -ScriptBlock $wmiScriptBlock -ArgumentList $netConf
                }

                if ($changes.Changes.Count -gt 0) {
                    $output.RestartNeeded = $true
                    if ($RestartService) {
                        if ($Pscmdlet.ShouldProcess("Restarting service for instance $($netConf.InstanceName) on $($netConf.ComputerName)")) {
                            try {
                                $null = Restart-DbaService -ComputerName $netConf.ComputerName -InstanceName $netConf.InstanceName -Credential $Credential -Type Engine -Force -EnableException -Confirm:$false
                                $output.Restarted = $true
                            } catch {
                                Write-Message -Level Warning -Message "A restart of the service for instance $($netConf.InstanceName) on $($netConf.ComputerName) failed ($_). Restart of instance is necessary for the new settings to take effect."
                            }
                        }
                    } else {
                        Write-Message -Level Warning -Message "A restart of the service for instance $($netConf.InstanceName) on $($netConf.ComputerName) is needed for the changes to take effect."
                    }
                }

                $output

            } catch {
                Stop-Function -Message "Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName) not possible." -Target $netConf.ComputerName -ErrorRecord $_ -Continue
            }
        }
    }
}
