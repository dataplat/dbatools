function Set-DbaPowerPlan {
    <#
    .SYNOPSIS
        Sets the SQL Server OS's Power Plan.

    .DESCRIPTION
        Sets the SQL Server OS's Power Plan. Defaults to High Performance which is best practice.

        If your organization uses a custom power plan that is considered best practice, specify -CustomPowerPlan.

        References:
        https://support.microsoft.com/en-us/kb/2207548
        http://www.sqlskills.com/blogs/glenn/windows-power-plan-effects-on-newer-intel-processors/

    .PARAMETER ComputerName
        The server(s) to set the Power Plan on.

    .PARAMETER Credential
        Specifies a PSCredential object to use in authenticating to the server(s), instead of the current user account.

    .PARAMETER PowerPlan
        Specifies the Power Plan that you wish to use. Valid options for this match the Windows default Power Plans of "Power Saver", "Balanced", and "High Performance".

    .PARAMETER CustomPowerPlan
        Specifies the name of a custom Power Plan to use.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: PowerPlan, OS, Configure
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: WMI access to servers

    .LINK
        https://dbatools.io/Set-DbaPowerPlan

    .EXAMPLE
        PS C:\> Set-DbaPowerPlan -ComputerName sqlserver2014a

        Sets the Power Plan to High Performance. Skips it if its already set.

    .EXAMPLE
        PS C:\> 'Server1', 'Server2' | Set-DbaPowerPlan -PowerPlaN Balanced

        Sets the Power Plan to Balanced for Server1 and Server2. Skips it if its already set.

    .EXAMPLE
        PS C:\> $cred = Get-Credential 'Domain\User'
        PS C:\> Set-DbaPowerPlan -ComputerName sqlserver2014a -Credential $cred

        Connects using alternative Windows credential and sets the Power Plan to High Performance. Skips it if its already set.

    .EXAMPLE
        PS C:\> Set-DbaPowerPlan -ComputerName sqlcluster -CustomPowerPlan 'Maximum Performance'

        Sets the Power Plan to the custom power plan called "Maximum Performance". Skips it if its already set.

    .EXAMPLE
        PS C:\> Test-DbaPowerPlan -ComputerName sqlcluster | Set-DbaPowerPlan

        Tests the Power Plan on sqlcluster and sets the Power Plan to High Performance. Skips it if its already set.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "SqlInstance")]
        [object[]]$ComputerName,
        [PSCredential]$Credential,
        [string]$PowerPlan = 'High Performance',
        [string]$CustomPowerPlan,
        [switch][Alias('Silent')]
        $EnableException
    )

    begin {
        if ($CustomPowerPlan.Length -gt 0) {
            $powerPlanRequested = $CustomPowerPlan
        } else {
            $powerPlanRequested = $PowerPlan
        }
        function Set-DbaPowerPlanInternal {
            [CmdletBinding(SupportsShouldProcess)]
            param(
                [object]$server,
                [PSCredential]$Credential
            )

            if (Test-Bound -ParameterName Credential) {
                $IncludeCred = $true
            }
            try {
                Write-Message -Level Verbose -Message "Testing connection to $server"
                $computerResolved = Resolve-DbaNetworkName -ComputerName $server -Credential $Credential

                $computerResolved = $computerResolved.FullComputerName
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server
                return
            }

            $splatDbaCmObject = @{
                ComputerName    = $computerResolved
                EnableException = $true
            }
            if ($IncludeCred) {
                $splatDbaCmObject["Credential"] = $Credential
            }

            try {
                Write-Message -Level Verbose -Message "Getting Power Plan information from $server."
                $currentplan = Get-DbaCmObject @splatDbaCmObject -ClassName Win32_PowerPlan -Namespace "root\cimv2\power"  | Where-Object IsActive -eq 'True'
                $currentplan = $currentplan.ElementName
            } catch {
                if ($_.Exception -match "namespace") {
                    Stop-Function -Message "Can't get Power Plan Info for $server. Unsupported operating system." -Continue -ErrorRecord $_ -Target $server
                } else {
                    Stop-Function -Message "Can't get Power Plan Info for $server. Check logs for more details." -Continue -ErrorRecord $_ -Target $server
                }
            }

            if ($null -eq $currentplan) {
                # the try/catch above isn't working, so make it silent and handle it here.
                Stop-Function -Message "Cannot get Power Plan for $server." -Category ConnectionError -ErrorRecord $_ -Target $server
                return
            }

            $planinfo = [PSCustomObject]@{
                Server            = $server
                PreviousPowerPlan = $currentplan
                ActivePowerPlan   = $powerPlanRequested
            }
            if ($Pscmdlet.ShouldProcess($powerPlanRequested, "Setting Powerplan on $server")) {
                if ($powerPlanRequested -ne $currentplan) {
                    if ($Pscmdlet.ShouldProcess($server, "Changing Power Plan from $CurrentPlan to $powerPlanRequested")) {
                        Write-Message -Level Verbose -Message "Creating CIMSession on $server over WSMan"
                        if ($IncludeCred) {
                            $cimSession = New-CimSession -ComputerName $server -ErrorAction SilentlyContinue -Credential $Credential
                        } else {
                            $cimSession = New-CimSession -ComputerName $server -ErrorAction SilentlyContinue
                        }
                        if ( -not $cimSession ) {
                            Write-Message -Level Verbose -Message "Creating CIMSession on $server over WSMan failed. Creating CIMSession on $server over DCom"
                            $sessionOption = New-CimSessionOption -Protocol DCom
                            if ($IncludeCred) {
                                $cimSession = New-CimSession -ComputerName $server -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
                            } else {
                                $cimSession = New-CimSession -ComputerName $server -SessionOption $sessionoption -ErrorAction SilentlyContinue
                            }
                        }
                        if ( $cimSession ) {
                            Write-Message -Level Verbose -Message "Setting Power Plan to $powerPlanRequested."

                            $cimInstance = Get-CimInstance -Name root\cimv2\power -Class win32_PowerPlan -Filter "ElementName = '$powerPlanRequested'"  -CimSession $CIMSession
                            if ($cimInstance) {
                                $cimResult = Invoke-CimMethod -InputObject $cimInstance[0] -MethodName Activate -CimSession $cimSession
                                if (!$cimResult) {
                                    Stop-Function -Message "Couldn't set the requested Power Plan '$powerPlanRequested' on $server." -Category ConnectionError -Target $server
                                    return
                                }
                            } else {
                                Stop-Function -Message "Couldn't find the requested Power Plan '$powerPlanRequested' on $server." -Category ConnectionError -Target $server
                                return
                            }
                        } else {
                            Stop-Function -Message "Couldn't set Power Plan on $server." -Category ConnectionError -ErrorRecord $_ -Target $server
                            return
                        }
                    }
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Stating power plan is already set to $powerPlanRequested, won't change.")) {
                        Write-Message -Level Verbose -Message "PowerPlan on $server is already set to $powerPlanRequested. Skipping."
                    }
                }

                return $planInfo
            }
        }

        $collection = New-Object System.Collections.ArrayList
        $processed = New-Object System.Collections.ArrayList
    }

    process {

        foreach ($server in $ComputerName) {
            if (($server.GetType()).Name -eq 'PSCustomObject') {
                if (($server -match 'ComputerName\=') -and ($server -match 'ActivePowerPlan\=')) {
                    Write-Message -Level Verbose -Message "Matched that value was piped from Test-DbaPowerPlan."
                    $server = $server.ComputerName.FullName
                } else {
                    Stop-Function -Message "Unknown object $server" -Category ConnectionError -ErrorRecord $_ -Target $ComputerName
                    return
                }
            }

            if ($server -notin $processed) {
                $null = $processed.Add($server)
            } else {
                continue
            }
            Write-Message -Level Verbose -Message "Calling Set-DbaPowerPlanInternal for $server"
            if (Test-Bound -ParameterName Credential) {
                $data = Set-DbaPowerPlanInternal -server $server -Credential $Credential
            } else {
                $data = Set-DbaPowerPlanInternal -server $server
            }

            if ($data.Count -gt 1) {
                $data.GetEnumerator() | ForEach-Object { $null = $collection.Add($_) }
            } else {
                $null = $collection.Add($data)
            }
        }
    }

    end {
        If ($Pscmdlet.ShouldProcess("console", "Showing results")) {
            return $collection
        }
    }
}