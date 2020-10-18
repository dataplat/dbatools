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
        Specifies the Power Plan that you wish to use.

        We use the English phrase "High Performance" by default. To specify Power Plans in another language, use this parameter (-PowerPlan Höchstleistung).

    .PARAMETER CustomPowerPlan
        Specifies the name of a custom Power Plan to use.

    .PARAMETER InputObject
        Enables piping from Get-DbaPowerPlan

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
        PS C:\> Set-DbaPowerPlan -ComputerName sql2017

        Sets the Power Plan to High Performance. Skips it if its already set.

    .EXAMPLE
        PS C:\> Set-DbaPowerPlan -ComputerName sql2017 -PowerPlan Höchstleistung

        Sets the PowerPlan on a German system to Höchstleistung.

        We use the English phrase "High Performance" by default. To specify Power Plans in another language, use the -PowerPlan parameter.

    .EXAMPLE
        PS C:\> 'Server1', 'Server2' | Set-DbaPowerPlan -PowerPlan Balanced

        Sets the Power Plan to Balanced for Server1 and Server2. Skips it if its already set.

    .EXAMPLE
        PS C:\> $cred = Get-Credential 'Domain\User'
        PS C:\> Set-DbaPowerPlan -ComputerName sql2017 -Credential $cred

        Connects using alternative Windows credential and sets the Power Plan to High Performance. Skips it if its already set.

    .EXAMPLE
        PS C:\> Set-DbaPowerPlan -ComputerName sqlcluster -CustomPowerPlan 'Maximum Performance'

        Sets the Power Plan to the custom power plan called "Maximum Performance". Skips it if its already set.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [PSCredential]$Credential,
        [string]$PowerPlan = 'High Performance',
        [string]$CustomPowerPlan,
        [parameter(ValueFromPipeline)]
        [pscustomobject[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ($CustomPowerPlan) {
            $powerPlanRequested = $CustomPowerPlan
        } else {
            $powerPlanRequested = $PowerPlan
        }
        function Set-DbaPowerPlanInternal {
            [CmdletBinding(SupportsShouldProcess)]
            param (
                [string]$ComputerName,
                [PSCredential]$Credential
            )

            if (Test-Bound -ParameterName Credential) {
                $IncludeCred = $true
            }
            try {
                Write-Message -Level Verbose -Message "Testing connection to $computer"
                $computerResolved = Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential

                $computerResolved = $computerResolved.FullComputerName
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $computer
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
                Write-Message -Level Verbose -Message "Getting Power Plan information from $computer."
                $currentplan = Get-DbaCmObject @splatDbaCmObject -ClassName Win32_PowerPlan -Namespace "root\cimv2\power" | Where-Object IsActive -eq 'True'
                $currentplan = $currentplan.ElementName
            } catch {
                if ($_.Exception -match "namespace") {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Unsupported operating system." -Continue -ErrorRecord $_ -Target $computer
                } else {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Check logs for more details." -Continue -ErrorRecord $_ -Target $computer
                }
            }

            if ($null -eq $currentplan) {
                # the try/catch above isn't working, so make it silent and handle it here.
                Stop-Function -Message "Cannot get Power Plan for $computer." -Category ConnectionError -ErrorRecord $_ -Target $computer
                return
            }

            $planinfo = [PSCustomObject]@{
                ComputerName      = $computer
                PreviousPowerPlan = $currentplan
                ActivePowerPlan   = $powerPlanRequested
            }
            if ($Pscmdlet.ShouldProcess($powerPlanRequested, "Setting Powerplan on $computer")) {
                if ($powerPlanRequested -ne $currentplan) {
                    if ($Pscmdlet.ShouldProcess($computer, "Changing Power Plan from $CurrentPlan to $powerPlanRequested")) {
                        Write-Message -Level Verbose -Message "Creating CIMSession on $computer over WSMan"
                        if ($IncludeCred) {
                            $cimSession = New-CimSession -ComputerName $computer -ErrorAction SilentlyContinue -Credential $Credential
                        } else {
                            $cimSession = New-CimSession -ComputerName $computer -ErrorAction SilentlyContinue
                        }
                        if (-not $cimSession) {
                            Write-Message -Level Verbose -Message "Creating CIMSession on $computer over WSMan failed. Creating CIMSession on $computer over DCom"
                            $sessionOption = New-CimSessionOption -Protocol DCom
                            if ($IncludeCred) {
                                $cimSession = New-CimSession -ComputerName $computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
                            } else {
                                $cimSession = New-CimSession -ComputerName $computer -SessionOption $sessionoption -ErrorAction SilentlyContinue
                            }
                        }
                        if ($cimSession) {
                            Write-Message -Level Verbose -Message "Setting Power Plan to $powerPlanRequested."

                            $cimInstance = Get-CimInstance -Namespace root\cimv2\power -ClassName win32_PowerPlan -Filter "ElementName = '$powerPlanRequested'" -CimSession $CIMSession
                            if ($cimInstance) {
                                # Because the activate method for powerplans is broken on windows server 2019, we use the powrprof.dll instead
                                [System.Guid]$powerPlanGuid = $cimInstance.InstanceID -replace '.*{(.*)}', '$1'
                                $scriptBlock = {
                                    Param ($Guid)
                                    $powerSetActiveSchemeDefinition = '[DllImport("powrprof.dll", CharSet = CharSet.Auto)] public static extern uint PowerSetActiveScheme(IntPtr RootPowerKey, Guid SchemeGuid);'
                                    $powrprof = Add-Type -MemberDefinition $powerSetActiveSchemeDefinition -Name 'Win32PowerSetActiveScheme' -Namespace 'Win32Functions' -PassThru
                                    $powrprof::PowerSetActiveScheme([System.IntPtr]::Zero, $Guid)
                                }
                                if ($IncludeCred) {
                                    $returnCode = Invoke-CommandWithFallback -ComputerName $computer -ScriptBlock $scriptBlock -ArgumentList $powerPlanGuid -Raw -Credential $Credential
                                } else {
                                    $returnCode = Invoke-CommandWithFallback -ComputerName $computer -ScriptBlock $scriptBlock -ArgumentList $powerPlanGuid -Raw
                                }
                                if ($returnCode -ne 0) {
                                    Stop-Function -Message "Couldn't set the requested Power Plan '$powerPlanRequested' on $computer (ReturnCode: $returnCode)." -Category ConnectionError -Target $computer
                                    return
                                }
                            } else {
                                Stop-Function -Message "Couldn't find the requested Power Plan '$powerPlanRequested' on $computer." -Category ConnectionError -Target $computer
                                return
                            }
                        } else {
                            Stop-Function -Message "Couldn't set Power Plan on $computer." -Category ConnectionError -ErrorRecord $_ -Target $computer
                            return
                        }
                    }
                } else {
                    if ($Pscmdlet.ShouldProcess($computer, "Stating power plan is already set to $powerPlanRequested, won't change.")) {
                        Write-Message -Level Verbose -Message "PowerPlan on $computer is already set to $powerPlanRequested. Skipping."
                    }
                }

                return $planInfo
            }
        }
    }

    process {
        # uses cim commands


        if (Test-Bound -ParameterName ComputerName) {
            $InputObject += Get-DbaPowerPlan -ComputerName $ComputerName -Credential $Credential
        }

        foreach ($pplan in $InputObject) {
            $computer = $pplan.ComputerName
            $Credential = $pplan.Credential
            Write-Message -Level Verbose -Message "Calling Set-DbaPowerPlanInternal for $computer"
            if (Test-Bound -ParameterName Credential) {
                $data = Set-DbaPowerPlanInternal -ComputerName $Computer -Credential $Credential
            } else {
                $data = Set-DbaPowerPlanInternal -ComputerName $Computer
            }

            if ($data.Count -gt 1) {
                $data.GetEnumerator() | ForEach-Object {
                    $_
                }
            } else {
                $data
            }
        }
    }
}