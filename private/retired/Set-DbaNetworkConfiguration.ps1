function Set-DbaNetworkConfiguration {
    <#
    .SYNOPSIS
        Modifies SQL Server network protocol settings including TCP/IP, Named Pipes, and Shared Memory configurations.

    .DESCRIPTION
        Modifies SQL Server network protocol settings through WMI, allowing you to enable or disable network protocols and configure TCP/IP properties like static or dynamic ports. This replaces the need to manually use SQL Server Configuration Manager for network changes.

        Common DBA scenarios include switching instances from dynamic to static ports for firewall rules, enabling TCP/IP for remote connections, or configuring specific IP addresses for multi-homed servers. You can also pass modified objects from Get-DbaNetworkConfiguration to make complex property changes.

        Network configuration changes require a SQL Server service restart to take effect - use the RestartService parameter to handle this automatically, otherwise you'll need to restart the service manually afterward.

        Uses remote SQL WMI by default with PowerShell remoting as a fallback. Requires administrative privileges on the target server.

        For detailed property explanations see: https://docs.microsoft.com/en-us/sql/tools/configuration-manager/sql-server-network-configuration

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER EnableProtocol
        Enables a specific SQL Server network protocol for client connections.
        Use SharedMemory for local-only connections, NamedPipes for legacy applications, or TcpIp for remote access.
        TCP/IP is required for remote connections and most modern applications.

    .PARAMETER DisableProtocol
        Disables a specific SQL Server network protocol to prevent client connections via that method.
        Commonly used to disable unneeded protocols for security or troubleshooting purposes.
        Be cautious disabling TCP/IP as it will prevent all remote connections to the instance.

    .PARAMETER DynamicPortForIPAll
        Configures the instance to use a random port assigned by Windows for all IP addresses.
        Use this for non-production environments or when you don't need predictable port numbers.
        Automatically enables TCP/IP protocol and sets ListenAll to true, clearing any existing static port configuration.

    .PARAMETER StaticPortForIPAll
        Configures the instance to use specific port numbers for all IP addresses instead of dynamic ports.
        Essential for production environments where firewall rules require predictable port numbers.
        Automatically enables TCP/IP protocol and sets ListenAll to true. Accepts multiple ports as comma-separated values.

    .PARAMETER IpAddress
        Restricts the instance to listen only on specified IP addresses instead of all available interfaces.
        Use this on multi-homed servers to control which network interfaces accept SQL Server connections.
        Format as "192.168.1.10" for dynamic ports or "192.168.1.10:1433" for static ports. IPv6 addresses need square brackets like "[::1]:1433".

    .PARAMETER RestartService
        Automatically restarts the SQL Server service when network configuration changes are made.
        Network configuration changes only take effect after a service restart, so use this to avoid manual restarts.
        Without this parameter, you must manually restart the SQL Server service for changes to become active.

    .PARAMETER InputObject
        Accepts a network configuration object from Get-DbaNetworkConfiguration for making complex property changes.
        Use this when you need to modify specific TCP/IP properties like KeepAlive values or make multiple configuration changes.
        The Get-DbaNetworkConfiguration command must use -OutputType Full to provide the complete configuration object.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: Network, Connection, SQLWMI
        Author: Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaNetworkConfiguration

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance whose network configuration was modified, containing the details of changes applied and service restart status.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Changes: Array of strings describing each configuration change made (e.g., "Changed TcpIpEnabled to True")
        - RestartNeeded: Boolean indicating whether a SQL Server service restart is required for changes to take effect
        - Restarted: Boolean indicating whether the SQL Server service was successfully restarted
        - Exception: System.Exception object if an error occurred during WMI operations (may be present if changes failed)

        All configuration changes require a SQL Server service restart to become active. If RestartNeeded is True and Restarted is False, you must manually restart the SQL Server service for the new settings to take effect.

    .EXAMPLE
        PS C:\> Set-DbaNetworkConfiguration -SqlInstance sql2016 -EnableProtocol SharedMemory -RestartService

        Ensures that the shared memory network protocol for the default instance on sql2016 is enabled.
        Restarts the service if needed.

    .EXAMPLE
        PS C:\> Set-DbaNetworkConfiguration -SqlInstance sql2016\test -StaticPortForIPAll 14331, 14332 -RestartService

        Ensures that the TCP/IP network protocol is enabled and configured to use the ports 14331 and 14332 for all IP addresses.
        Restarts the service if needed.

    .EXAMPLE
        PS C:\> $netConf = Get-DbaNetworkConfiguration -SqlInstance sqlserver2014a
        PS C:\> $netConf.TcpIpProperties.KeepAlive = 60000
        PS C:\> $netConf | Set-DbaNetworkConfiguration -RestartService -Confirm:$false

        Changes the value of the KeepAlive property for the default instance on sqlserver2014a and restarts the service.
        Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Set-DbaNetworkConfiguration -SqlInstance sql2016\test -IpAddress 192.168.3.41:1433 -RestartService

        Ensures that the TCP/IP network protocol is enabled and configured to only listen on port 1433 of IP address 192.168.3.41.
        Restarts the service if needed.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High", DefaultParameterSetName = 'NonPipeline')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateSet('SharedMemory', 'NamedPipes', 'TcpIp')]
        [string]$EnableProtocol,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateSet('SharedMemory', 'NamedPipes', 'TcpIp')]
        [string]$DisableProtocol,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [switch]$DynamicPortForIPAll,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [int[]]$StaticPortForIPAll,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$IpAddress,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$RestartService,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [object[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $wmiScriptBlock = {
            # This scriptblock will be processed by Invoke-Command2 on the target machine.
            # We take on object as the first parameter which has to include the instance name and the target network configuration.
            $targetConf = $args[0]
            $changes = @()
            $verbose = @()
            $exception = $null

            try {
                $verbose += "Starting initialization of WMI object"

                # As we go remote, ensure the assembly is loaded
                [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
                $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
                $result = $wmi.Initialize()

                $verbose += "Initialization of WMI object finished with $result"

                # If WMI object is empty, there are no client protocols - so we test for that to see if initialization was successful
                $verbose += "Found $($wmi.ServerInstances.Count) instances and $($wmi.ClientProtocols.Count) client protocols inside of WMI object"

                $verbose += "Getting server protocols for $($targetConf.InstanceName)"
                $wmiServerProtocols = ($wmi.ServerInstances | Where-Object { $_.Name -eq $targetConf.InstanceName } ).ServerProtocols

                $verbose += 'Getting server protocol shared memory'
                $wmiSpSm = $wmiServerProtocols | Where-Object { $_.Name -eq 'Sm' }
                if ($null -eq $targetConf.SharedMemoryEnabled) {
                    $verbose += 'SharedMemoryEnabled not in target object'
                } elseif ($wmiSpSm.IsEnabled -ne $targetConf.SharedMemoryEnabled) {
                    $wmiSpSm.IsEnabled = $targetConf.SharedMemoryEnabled
                    $wmiSpSm.Alter()
                    $changes += "Changed SharedMemoryEnabled to $($targetConf.SharedMemoryEnabled)"
                }

                $verbose += 'Getting server protocol named pipes'
                $wmiSpNp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Np' }
                if ($null -eq $targetConf.NamedPipesEnabled) {
                    $verbose += 'NamedPipesEnabled not in target object'
                } elseif ($wmiSpNp.IsEnabled -ne $targetConf.NamedPipesEnabled) {
                    $wmiSpNp.IsEnabled = $targetConf.NamedPipesEnabled
                    $wmiSpNp.Alter()
                    $changes += "Changed NamedPipesEnabled to $($targetConf.NamedPipesEnabled)"
                }

                $verbose += 'Getting server protocol TCP/IP'
                $wmiSpTcp = $wmiServerProtocols | Where-Object { $_.Name -eq 'Tcp' }
                if ($null -eq $targetConf.TcpIpEnabled) {
                    $verbose += 'TcpIpEnabled not in target object'
                } elseif ($wmiSpTcp.IsEnabled -ne $targetConf.TcpIpEnabled) {
                    $wmiSpTcp.IsEnabled = $targetConf.TcpIpEnabled
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpEnabled to $($targetConf.TcpIpEnabled)"
                }

                $verbose += 'Getting properties for server protocol TCP/IP'
                $wmiSpTcpEnabled = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'Enabled' }
                if ($null -eq $targetConf.TcpIpProperties.Enabled) {
                    $verbose += 'TcpIpProperties.Enabled not in target object'
                } elseif ($wmiSpTcpEnabled.Value -ne $targetConf.TcpIpProperties.Enabled) {
                    $wmiSpTcpEnabled.Value = $targetConf.TcpIpProperties.Enabled
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpProperties.Enabled to $($targetConf.TcpIpProperties.Enabled)"
                }

                $wmiSpTcpKeepAlive = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'KeepAlive' }
                if ($null -eq $targetConf.TcpIpProperties.KeepAlive) {
                    $verbose += 'TcpIpProperties.KeepAlive not in target object'
                } elseif ($wmiSpTcpKeepAlive.Value -ne $targetConf.TcpIpProperties.KeepAlive) {
                    $wmiSpTcpKeepAlive.Value = $targetConf.TcpIpProperties.KeepAlive
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpProperties.KeepAlive to $($targetConf.TcpIpProperties.KeepAlive)"
                }

                $wmiSpTcpListenOnAllIPs = $wmiSpTcp.ProtocolProperties | Where-Object { $_.Name -eq 'ListenOnAllIPs' }
                if ($null -eq $targetConf.TcpIpProperties.ListenAll) {
                    $verbose += 'TcpIpProperties.ListenAll not in target object'
                } elseif ($wmiSpTcpListenOnAllIPs.Value -ne $targetConf.TcpIpProperties.ListenAll) {
                    $wmiSpTcpListenOnAllIPs.Value = $targetConf.TcpIpProperties.ListenAll
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpIpProperties.ListenAll to $($targetConf.TcpIpProperties.ListenAll)"
                }

                $verbose += 'Getting properties for IPn'
                $wmiIPn = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -ne 'IPAll' }
                foreach ($ip in $wmiIPn) {
                    $ipTarget = $targetConf.TcpIpAddresses | Where-Object { $_.Name -eq $ip.Name }

                    $ipActive = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'Active' }
                    if ($null -eq $ipTarget.Active) {
                        $verbose += 'Active not in target IP address object'
                    } elseif ($ipActive.Value -ne $ipTarget.Active) {
                        $ipActive.Value = $ipTarget.Active
                        $wmiSpTcp.Alter()
                        $changes += "Changed Active for $($ip.Name) to $($ipTarget.Active)"
                    }

                    $ipEnabled = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'Enabled' }
                    if ($null -eq $ipTarget.Enabled) {
                        $verbose += 'Enabled not in target IP address object'
                    } elseif ($ipEnabled.Value -ne $ipTarget.Enabled) {
                        $ipEnabled.Value = $ipTarget.Enabled
                        $wmiSpTcp.Alter()
                        $changes += "Changed Enabled for $($ip.Name) to $($ipTarget.Enabled)"
                    }

                    $ipIpAddress = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'IpAddress' }
                    if ($null -eq $ipTarget.IpAddress) {
                        $verbose += 'IpAddress not in target IP address object'
                    } elseif ($ipIpAddress.Value -ne $ipTarget.IpAddress) {
                        $ipIpAddress.Value = $ipTarget.IpAddress
                        $wmiSpTcp.Alter()
                        $changes += "Changed IpAddress for $($ip.Name) to $($ipTarget.IpAddress)"
                    }

                    $ipTcpDynamicPorts = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' }
                    if ($null -eq $ipTarget.TcpDynamicPorts) {
                        $verbose += 'TcpDynamicPorts not in target IP address object'
                    } elseif ($ipTcpDynamicPorts.Value -ne $ipTarget.TcpDynamicPorts) {
                        $ipTcpDynamicPorts.Value = $ipTarget.TcpDynamicPorts
                        $wmiSpTcp.Alter()
                        $changes += "Changed TcpDynamicPorts for $($ip.Name) to $($ipTarget.TcpDynamicPorts)"
                    }

                    $ipTcpPort = $ip.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
                    if ($null -eq $ipTarget.TcpPort) {
                        $verbose += 'TcpPort not in target IP address object'
                    } elseif ($ipTcpPort.Value -ne $ipTarget.TcpPort) {
                        $ipTcpPort.Value = $ipTarget.TcpPort
                        $wmiSpTcp.Alter()
                        $changes += "Changed TcpPort for $($ip.Name) to $($ipTarget.TcpPort)"
                    }
                }

                $verbose += 'Getting properties for IPAll'
                $wmiIPAll = $wmiSpTcp.IPAddresses | Where-Object { $_.Name -eq 'IPAll' }
                $ipTarget = $targetConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }

                $ipTcpDynamicPorts = $wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpDynamicPorts' }
                if ($null -eq $ipTarget.TcpDynamicPorts) {
                    $verbose += 'TcpDynamicPorts not in target IP address object'
                } elseif ($ipTcpDynamicPorts.Value -ne $ipTarget.TcpDynamicPorts) {
                    $ipTcpDynamicPorts.Value = $ipTarget.TcpDynamicPorts
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpDynamicPorts for $($wmiIPAll.Name) to $($ipTarget.TcpDynamicPorts)"
                }

                $ipTcpPort = $wmiIPAll.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
                if ($null -eq $ipTarget.TcpPort) {
                    $verbose += 'TcpPort not in target IP address object'
                } elseif ($ipTcpPort.Value -ne $ipTarget.TcpPort) {
                    $ipTcpPort.Value = $ipTarget.TcpPort
                    $wmiSpTcp.Alter()
                    $changes += "Changed TcpPort for $($wmiIPAll.Name) to $($ipTarget.TcpPort)"
                }
            } catch {
                $exception = $_
            }

            [PSCustomObject]@{
                Changes   = $changes
                Verbose   = $verbose
                Exception = $exception
            }
        }
    }

    process {
        if ($SqlInstance -and (Test-Bound -Not -ParameterName EnableProtocol, DisableProtocol, DynamicPortForIPAll, StaticPortForIPAll, IpAddress)) {
            Stop-Function -Message "You must choose an action if SqlInstance is used."
            return
        }

        if ($SqlInstance -and (Test-Bound -ParameterName EnableProtocol, DisableProtocol, DynamicPortForIPAll, StaticPortForIPAll, IpAddress -Not -Max 1)) {
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

            if ($EnableProtocol) {
                if ($netConf."${EnableProtocol}Enabled") {
                    Write-Message -Level Verbose -Message "Protocol $EnableProtocol is already enabled on $instance."
                } else {
                    Write-Message -Level Verbose -Message "Will enable protocol $EnableProtocol on $instance."
                    $netConf."${EnableProtocol}Enabled" = $true
                    if ($EnableProtocol -eq 'TcpIp') {
                        $netConf.TcpIpProperties.Enabled = $true
                    }
                }
            }

            if ($DisableProtocol) {
                if ($netConf."${DisableProtocol}Enabled") {
                    Write-Message -Level Verbose -Message "Will disable protocol $EnableProtocol on $instance."
                    $netConf."${DisableProtocol}Enabled" = $false
                    if ($DisableProtocol -eq 'TcpIp') {
                        $netConf.TcpIpProperties.Enabled = $false
                    }
                } else {
                    Write-Message -Level Verbose -Message "Protocol $EnableProtocol is already disabled on $instance."
                }
            }

            if ($DynamicPortForIPAll) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance."
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if (-not $netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to True on $instance."
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
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance."
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if (-not $netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.ListenAll = $true
                }
                $ipAll = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IPAll to '' on $instance."
                $ipAll.TcpDynamicPorts = ''
                $port = $StaticPortForIPAll -join ','
                Write-Message -Level Verbose -Message "Will set property TcpPort of IPAll to '$port' on $instance."
                $ipAll.TcpPort = $port
            }

            if ($IpAddress) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance."
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance."
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if ($netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to False on $instance."
                    $netConf.TcpIpProperties.ListenAll = $false
                }
                foreach ($ip in ($netConf.TcpIpAddresses | Where-Object { $_.Name -ne 'IPAll' })) {
                    if ($ip.IpAddress -match ':') {
                        # IPv6: Remove interface id
                        $address = $ip.IpAddress -replace '^(.*)%.*$', '$1'
                    } else {
                        # IPv4: Do nothing special
                        $address = $ip.IpAddress
                    }
                    # Is the current IP one of those to be configured?
                    $isTarget = $false
                    foreach ($listenIP in $IpAddress) {
                        if ($listenIP -match '^\[(.+)\]:?(\d*)$') {
                            # IPv6
                            $listenAddress = $Matches.1
                            $listenPort = $Matches.2
                        } elseif ($listenIP -match '^([^:]+):?(\d*)$') {
                            # IPv4
                            $listenAddress = $Matches.1
                            $listenPort = $Matches.2
                        } else {
                            Write-Message -Level Verbose -Message "$listenIP is not a valid IP address. Skipping."
                            continue
                        }
                        if ($listenAddress -eq $address) {
                            $isTarget = $true
                            break
                        }
                    }
                    if ($isTarget) {
                        if (-not $ip.Enabled) {
                            Write-Message -Level Verbose -Message "Will set property Enabled of IP address $($ip.IpAddress) to True on $instance."
                            $ip.Enabled = $true
                        }
                        if ($listenPort) {
                            # configure for static port
                            if ($ip.TcpDynamicPorts -ne '') {
                                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IP address $($ip.IpAddress) to '' on $instance."
                                $ip.TcpDynamicPorts = ''
                            }
                            if ($ip.TcpPort -ne $listenPort) {
                                Write-Message -Level Verbose -Message "Will set property TcpPort of IP address $($ip.IpAddress) to '$listenPort' on $instance."
                                $ip.TcpPort = $listenPort
                            }
                        } else {
                            # configure for dynamic port
                            if ($ip.TcpDynamicPorts -ne '0') {
                                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IP address $($ip.IpAddress) to '0' on $instance."
                                $ip.TcpDynamicPorts = '0'
                            }
                            if ($ip.TcpPort -ne '') {
                                Write-Message -Level Verbose -Message "Will set property TcpPort of IP address $($ip.IpAddress) to '' on $instance."
                                $ip.TcpPort = ''
                            }
                        }
                    } else {
                        if ($ip.Enabled) {
                            Write-Message -Level Verbose -Message "Will set property Enabled of IP address $($ip.IpAddress) to False on $instance."
                            $ip.Enabled = $false
                        }
                    }
                }
            }

            $InputObject += $netConf
        }

        foreach ($netConf in $InputObject) {
            try {
                $output = [PSCustomObject]@{
                    ComputerName  = $netConf.ComputerName
                    InstanceName  = $netConf.InstanceName
                    SqlInstance   = $netConf.SqlInstance
                    Changes       = @()
                    RestartNeeded = $false
                    Restarted     = $false
                }

                if ($Pscmdlet.ShouldProcess("Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName)")) {
                    $computerName = Resolve-DbaComputerName -ComputerName $netConf.ComputerName -Credential $Credential
                    $null = Test-ElevationRequirement -ComputerName $computerName -EnableException $true
                    $result = Invoke-Command2 -ScriptBlock $wmiScriptBlock -ArgumentList $netConf -ComputerName $computerName -Credential $Credential -ErrorAction Stop
                    foreach ($verbose in $result.Verbose) {
                        Write-Message -Level Verbose -Message $verbose
                    }
                    $output.Changes = $result.Changes
                    if ($result.Exception) {
                        # The new code pattern for WMI calls is used where all exceptions are catched and return as part of an object.
                        $output.Exception = $result.Exception
                        Write-Message -Level Verbose -Message "Execution against $computerName failed with: $($result.Exception)"
                        Stop-Function -Message "Setting network configuration for instance $($netConf.InstanceName) on $($netConf.ComputerName) failed with: $($result.Exception)" -Target $netConf.ComputerName -ErrorRecord $result.Exception -Continue
                    }
                }

                if ($result.Changes.Count -gt 0) {
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