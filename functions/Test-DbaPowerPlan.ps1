function Test-DbaPowerPlan {
    <#
    .SYNOPSIS
        Checks the Power Plan settings for compliance with best practices, which recommend High Performance for SQL Server.

    .DESCRIPTION
        Checks the Power Plan settings on a computer against best practices recommendations.
        Each server's name, the active and the recommended Power Plan and an IsBestPractice field are returned.

        If your organization uses a different Power Plan that is considered best practice, specify -PowerPlan.

        References:
        https://support.microsoft.com/en-us/kb/2207548
        http://www.sqlskills.com/blogs/glenn/windows-power-plan-effects-on-newer-intel-processors/

    .PARAMETER ComputerName
        The server(s) to check Power Plan settings on.

    .PARAMETER Credential
        Specifies a PSCredential object to use in authenticating to the server(s), instead of the current user account.

    .PARAMETER PowerPlan
        If your organization uses a different power plan that's considered best practice, specify it here.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: PowerPlan
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaPowerPlan

    .EXAMPLE
        PS C:\> Test-DbaPowerPlan -ComputerName sqlserver2014a

        Checks the Power Plan settings for sqlserver2014a and indicates whether or not it complies with best practices.

    .EXAMPLE
        PS C:\> Test-DbaPowerPlan -ComputerName sqlserver2014a -PowerPlan 'Maximum Performance'

        Checks the Power Plan settings for sqlserver2014a and indicates whether or not it is set to the Power Plan "Maximum Performance".

    .EXAMPLE
        PS C:\> 'newserver1', 'newserver2' | Test-DbaPowerPlan

        Checks the Power Plan settings for newserver1 and newserver2 and indicates whether or not they comply with best practices.

    .EXAMPLE
        PS C:\> Get-DbaPowerPlan -ComputerName oldserver | Test-DbaPowerPlan -ComputerName newserver1, newserver2

        Uses the Power Plan of oldserver as best practice and tests the Power Plan of newserver1 and newserver2 against that.

    #>
    param (
        [parameter(Mandatory, ValueFromPipelineByPropertyName, ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias("CustomPowerPlan")]
        [string]$PowerPlan,
        [switch]$EnableException
    )

    begin {
        $bpPowerPlan = [PSCustomObject]@{
            InstanceID = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            PowerPlan  = $null
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                Write-Message -Level Verbose -Message "Getting Power Plans for $computer."
                $powerPlans = Get-DbaPowerPlan -ComputerName $computer -Credential $Credential -List -EnableException
            } catch {
                Stop-Function -Message "Can't get Power Plan Info for $computer. Check logs for more details." -Continue -ErrorRecord $_ -Target $computer
            }

            if ($PowerPlan) {
                Write-Message -Level Verbose -Message "Using Power Plan '$PowerPlan' as best practice."
                $bpPowerPlan.PowerPlan = $PowerPlan
                $bpPowerPlan.InstanceID = ($powerPlans | Where-Object { $_.PowerPlan -eq $PowerPlan }).InstanceID
                if ($null -eq $bpPowerplan.InstanceID) {
                    Write-Message -Level Verbose -Message "Unable to find Power Plan '$PowerPlan' on $computer."
                    $bpPowerPlan.PowerPlan = "You do not have the Power Plan '$PowerPlan' installed on this machine."
                }
            } else {
                $bpPowerPlan.PowerPlan = ($powerPlans | Where-Object { $_.InstanceID -eq $bpPowerPlan.InstanceID }).PowerPlan
                if ($null -eq $bpPowerplan.PowerPlan) {
                    Write-Message -Level Verbose -Message "Unable to find Power Plan 'High performance' on $computer."
                    $bpPowerPlan.PowerPlan = "You do not have the high performance plan installed on this machine."
                }
            }

            $activePowerPlan = $powerPlans | Where-Object IsActive -eq 'True'
            Write-Message -Level Verbose -Message "Recommended GUID is $($bpPowerPlan.InstanceID) and you have $($activePowerPlan.InstanceID)."

            if ($activePowerPlan.InstanceID -eq $bpPowerPlan.InstanceID) {
                $isBestPractice = $true
            } else {
                $isBestPractice = $false
            }

            [PSCustomObject]@{
                ComputerName          = $computer
                ActiveInstanceId      = $activePowerPlan.InstanceID
                ActivePowerPlan       = $activePowerPlan.PowerPlan
                RecommendedInstanceId = $bpPowerPlan.InstanceID
                RecommendedPowerPlan  = $bpPowerPlan.PowerPlan
                IsBestPractice        = $isBestPractice
                Credential            = $Credential
            } | Select-DefaultView -Property ComputerName, ActivePowerPlan, RecommendedPowerPlan, IsBestPractice
        }
    }
}