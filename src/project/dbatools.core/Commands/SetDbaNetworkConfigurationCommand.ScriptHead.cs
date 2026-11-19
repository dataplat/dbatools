#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Set-DbaNetworkConfiguration hop script, FIRST half (the begin-scope $wmiScriptBlock
/// + validations + the SqlInstance mutation loop). The verbatim body exceeds the
/// 400-line file maximum in one file, so the script is split at a loop boundary into
/// two compile-time-concatenated constants (the W3-081 pattern) - the joined text is
/// byte-identical to the single-constant form (see SetDbaNetworkConfigurationCommand.cs).
/// </summary>
public sealed partial class SetDbaNetworkConfigurationCommand
{
    internal const string ProcessScriptHead = """
param($SqlInstance, $Credential, $EnableProtocol, $DisableProtocol, $DynamicPortForIPAll, $StaticPortForIPAll, $IpAddress, $RestartService, $InputObject, $EnableException, $__boundEnableProtocol, $__boundDisableProtocol, $__boundDynamicPortForIPAll, $__boundStaticPortForIPAll, $__boundIpAddress, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$Credential, [string]$EnableProtocol, [string]$DisableProtocol, $DynamicPortForIPAll, [int[]]$StaticPortForIPAll, [string[]]$IpAddress, $RestartService, [object[]]$InputObject, $EnableException, $__boundEnableProtocol, $__boundDisableProtocol, $__boundDynamicPortForIPAll, $__boundStaticPortForIPAll, $__boundIpAddress, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record restore: the gate/try-assigned $result read outside the gate
    if ($null -ne $__state) {
        $result = $__state.result
    }

    # ATTRIBUTION SHIM (the W3-084/W3-092 Get-PSCallStack class): Test-ElevationRequirement
    # stamps its Stop-Function with (Get-PSCallStack)[1].Command; called bare from this hop
    # that frame is the scriptblock. The named wrapper restores the source's own frame -
    # with -EnableException $true the helper THROWS, so the identity rides the exception.
    function Set-DbaNetworkConfiguration {
        param($__splat)
        Test-ElevationRequirement @__splat
    }

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

    . {
        # $SqlInstance -and (Test-Bound -Not -ParameterName EnableProtocol, DisableProtocol, DynamicPortForIPAll, StaticPortForIPAll, IpAddress) = NONE of the five bound
        if ($SqlInstance -and (-not ($__boundEnableProtocol -or $__boundDisableProtocol -or $__boundDynamicPortForIPAll -or $__boundStaticPortForIPAll -or $__boundIpAddress))) {
            Stop-Function -Message "You must choose an action if SqlInstance is used." -FunctionName Set-DbaNetworkConfiguration
            return
        }

        # $SqlInstance -and (Test-Bound -ParameterName <the five> -Not -Max 1) = NOT exactly one bound
        if ($SqlInstance -and ((([int][bool]$__boundEnableProtocol) + ([int][bool]$__boundDisableProtocol) + ([int][bool]$__boundDynamicPortForIPAll) + ([int][bool]$__boundStaticPortForIPAll) + ([int][bool]$__boundIpAddress)) -ne 1)) {
            Stop-Function -Message "Only one action is allowed at a time." -FunctionName Set-DbaNetworkConfiguration
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Get network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                $netConf = Get-DbaNetworkConfiguration -SqlInstance $instance -Credential $Credential -EnableException
            } catch {
                Stop-Function -Message "Failed to collect network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue -FunctionName Set-DbaNetworkConfiguration
            }

            if ($EnableProtocol) {
                if ($netConf."${EnableProtocol}Enabled") {
                    Write-Message -Level Verbose -Message "Protocol $EnableProtocol is already enabled on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                } else {
                    Write-Message -Level Verbose -Message "Will enable protocol $EnableProtocol on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    $netConf."${EnableProtocol}Enabled" = $true
                    if ($EnableProtocol -eq 'TcpIp') {
                        $netConf.TcpIpProperties.Enabled = $true
                    }
                }
            }

            if ($DisableProtocol) {
                if ($netConf."${DisableProtocol}Enabled") {
                    Write-Message -Level Verbose -Message "Will disable protocol $EnableProtocol on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    $netConf."${DisableProtocol}Enabled" = $false
                    if ($DisableProtocol -eq 'TcpIp') {
                        $netConf.TcpIpProperties.Enabled = $false
                    }
                } else {
                    Write-Message -Level Verbose -Message "Protocol $EnableProtocol is already disabled on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                }
            }

            if ($DynamicPortForIPAll) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if (-not $netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to True on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    $netConf.TcpIpProperties.ListenAll = $true
                }
                $ipAll = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IPAll to '0' on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                $ipAll.TcpDynamicPorts = '0'
                Write-Message -Level Verbose -Message "Will set property TcpPort of IPAll to '' on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                $ipAll.TcpPort = ''
            }

            if ($StaticPortForIPAll) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if (-not $netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to True on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    $netConf.TcpIpProperties.ListenAll = $true
                }
                $ipAll = $netConf.TcpIpAddresses | Where-Object { $_.Name -eq 'IPAll' }
                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IPAll to '' on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                $ipAll.TcpDynamicPorts = ''
                $port = $StaticPortForIPAll -join ','
                Write-Message -Level Verbose -Message "Will set property TcpPort of IPAll to '$port' on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                $ipAll.TcpPort = $port
            }

            if ($IpAddress) {
                if (-not $netConf.TcpIpEnabled) {
                    Write-Message -Level Verbose -Message "Will enable protocol TcpIp on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    $netConf.TcpIpEnabled = $true
                }
                if (-not $netConf.TcpIpProperties.Enabled) {
                    Write-Message -Level Verbose -Message "Will set property Enabled of protocol TcpIp to True on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                    $netConf.TcpIpProperties.Enabled = $true
                }
                if ($netConf.TcpIpProperties.ListenAll) {
                    Write-Message -Level Verbose -Message "Will set property ListenAll of protocol TcpIp to False on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
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
                            Write-Message -Level Verbose -Message "$listenIP is not a valid IP address. Skipping." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                            continue
                        }
                        if ($listenAddress -eq $address) {
                            $isTarget = $true
                            break
                        }
                    }
                    if ($isTarget) {
                        if (-not $ip.Enabled) {
                            Write-Message -Level Verbose -Message "Will set property Enabled of IP address $($ip.IpAddress) to True on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                            $ip.Enabled = $true
                        }
                        if ($listenPort) {
                            # configure for static port
                            if ($ip.TcpDynamicPorts -ne '') {
                                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IP address $($ip.IpAddress) to '' on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                                $ip.TcpDynamicPorts = ''
                            }
                            if ($ip.TcpPort -ne $listenPort) {
                                Write-Message -Level Verbose -Message "Will set property TcpPort of IP address $($ip.IpAddress) to '$listenPort' on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                                $ip.TcpPort = $listenPort
                            }
                        } else {
                            # configure for dynamic port
                            if ($ip.TcpDynamicPorts -ne '0') {
                                Write-Message -Level Verbose -Message "Will set property TcpDynamicPorts of IP address $($ip.IpAddress) to '0' on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                                $ip.TcpDynamicPorts = '0'
                            }
                            if ($ip.TcpPort -ne '') {
                                Write-Message -Level Verbose -Message "Will set property TcpPort of IP address $($ip.IpAddress) to '' on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                                $ip.TcpPort = ''
                            }
                        }
                    } else {
                        if ($ip.Enabled) {
                            Write-Message -Level Verbose -Message "Will set property Enabled of IP address $($ip.IpAddress) to False on $instance." -FunctionName Set-DbaNetworkConfiguration -ModuleName "dbatools"
                            $ip.Enabled = $false
                        }
                    }
                }
            }

            $InputObject += $netConf
        }
""";
}
