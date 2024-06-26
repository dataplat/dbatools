function Set-DbaPowerPlan {
    <#
    .SYNOPSIS
        Sets the SQL Server OS's Power Plan.

    .DESCRIPTION
        Sets the SQL Server OS's Power Plan. Defaults to High Performance which is best practice.

        If your organization uses a different power plan that is considered best practice, specify -PowerPlan.

        References:
        https://support.microsoft.com/en-us/kb/2207548
        http://www.sqlskills.com/blogs/glenn/windows-power-plan-effects-on-newer-intel-processors/

    .PARAMETER ComputerName
        The server(s) to set the Power Plan on.

    .PARAMETER Credential
        Specifies a PSCredential object to use in authenticating to the server(s), instead of the current user account.

    .PARAMETER PowerPlan
        If your organization uses a different Power Plan that's considered best practice, specify it here.
        Use Get-DbaPowerPlan -List to get all available Power Plans on a computer.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: PowerPlan, OS, Configure, Utility
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
        PS C:\> 'Server1', 'Server2' | Set-DbaPowerPlan -PowerPlan Balanced

        Sets the Power Plan to Balanced for Server1 and Server2. Skips it if its already set.

    .EXAMPLE
        PS C:\> $cred = Get-Credential 'Domain\User'
        PS C:\> Set-DbaPowerPlan -ComputerName sql2017 -Credential $cred

        Connects using alternative Windows credential and sets the Power Plan to High Performance. Skips it if its already set.

    .EXAMPLE
        PS C:\> Set-DbaPowerPlan -ComputerName sqlcluster -PowerPlan 'Maximum Performance'

        Sets the Power Plan to "Maximum Performance". Skips it if its already set.

    .EXAMPLE
        PS C:\> Get-DbaPowerPlan -ComputerName oldserver | Set-DbaPowerPlan -ComputerName newserver1, newserver2

        Uses the Power Plan of oldserver as best practice and sets the Power Plan of newserver1 and newserver2 accordingly.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipelineByPropertyName, ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("CustomPowerPlan", "RecommendedPowerPlan")]
        [string]$PowerPlan,
        [switch]$EnableException
    )

    process {
        foreach ($computer in $ComputerName) {
            try {
                Write-Message -Level Verbose -Message "Getting and testing Power Plans on $computer using '$PowerPlan' as best practice."
                $change = Test-DbaPowerPlan -ComputerName $computer -Credential $Credential -PowerPlan $PowerPlan -EnableException
            } catch {
                if ($_.Exception -match "namespace") {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Unsupported operating system." -Continue -ErrorRecord $_ -Target $computer
                } elseif ($_.Exception -match "credentials are known to not work") {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Login failure for $($Credential.UserName)." -Continue -ErrorRecord $_ -Target $computer
                } else {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Check logs for more details." -Continue -ErrorRecord $_ -Target $computer
                }
            }

            $instanceId = $change.ActiveInstanceId
            $powerPlanActive = $change.ActivePowerPlan
            $instanceIdRequested = $change.RecommendedInstanceId
            $powerPlanRequested = $change.RecommendedPowerPlan

            if ($null -eq $instanceIdRequested) {
                Stop-Function -Message "You do not have the Power Plan '$PowerPlan' installed on $computer. Skipping." -Continue -Target $computer
            }

            $output = [PSCustomObject]@{
                ComputerName       = $computer
                PreviousInstanceId = $instanceId
                PreviousPowerPlan  = $powerPlanActive
                ActiveInstanceId   = $instanceId
                ActivePowerPlan    = $powerPlanActive
                IsChanged          = $false
            }

            if ($change.IsBestPractice) {
                if ($Pscmdlet.ShouldProcess($computer, "Stating power plan is already set to $powerPlanRequested, won't change.")) {
                    Write-Message -Level Verbose -Message "PowerPlan on $computer is already set to $powerPlanRequested. Skipping."
                    $output | Select-DefaultView -Property ComputerName, PreviousPowerPlan, ActivePowerPlan, IsChanged
                }
            } else {
                if ($Pscmdlet.ShouldProcess($computer, "Changing Power Plan from $powerPlanActive to $powerPlanRequested")) {
                    [System.Guid]$powerPlanGuid = $instanceIdRequested
                    $scriptBlock = {
                        Param ($Guid)
                        $powerSetActiveSchemeDefinition = '[DllImport("powrprof.dll", CharSet = CharSet.Auto)] public static extern uint PowerSetActiveScheme(IntPtr RootPowerKey, Guid SchemeGuid);'
                        $powrprof = Add-Type -MemberDefinition $powerSetActiveSchemeDefinition -Name 'Win32PowerSetActiveScheme' -Namespace 'Win32Functions' -PassThru
                        $powrprof::PowerSetActiveScheme([System.IntPtr]::Zero, $Guid)
                    }
                    try {
                        $resolvedComputerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential -EnableException).FullComputerName
                    } catch {
                        try {
                            $resolvedComputerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential -Turbo -EnableException).FullComputerName
                        } catch {
                            $resolvedComputerName = $computer
                        }
                    }
                    try {
                        $returnCode = Invoke-Command2 -ComputerName $resolvedComputerName -Credential $Credential -ArgumentList $powerPlanGuid -ScriptBlock $scriptBlock -Raw
                        if ($returnCode -ne 0) {
                            Stop-Function -Message "Couldn't set the requested Power Plan '$powerPlanRequested' on $computer (ReturnCode: $returnCode)." -Category ConnectionError -Target $computer -Continue
                        }
                        $output.IsChanged = $true
                        $output.ActiveInstanceId = $instanceIdRequested
                        $output.ActivePowerPlan = $powerPlanRequested
                    } catch {
                        Stop-Function -Message "Failed to connect to $computer." -ErrorRecord $_ -Target $computer -Continue
                    }
                    $output | Select-DefaultView -Property ComputerName, PreviousPowerPlan, ActivePowerPlan, IsChanged
                }
            }
        }
    }
}