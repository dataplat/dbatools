function Test-DbaPowerPlan {
    <#
    .SYNOPSIS
        Tests Windows Power Plan settings against SQL Server best practices and identifies non-compliant systems.

    .DESCRIPTION
        Audits Windows Power Plan settings on SQL Server hosts to ensure compliance with Microsoft's performance recommendations. SQL Server runs optimally with the "High Performance" power plan, which prevents CPU throttling and ensures consistent performance under load.

        This function compares the currently active power plan against the recommended "High Performance" plan (or a custom plan you specify) and returns a compliance report. This is essential for SQL Server environments where power management can significantly impact query performance and response times.

        Returns detailed information including the active power plan, recommended plan, and a clear IsBestPractice indicator for each system tested. Use this for regular compliance audits, new server validations, or troubleshooting performance issues that might be related to power management settings.

        If your organization uses a different Power Plan that is considered best practice, specify -PowerPlan to test against that instead.

        References:
        https://support.microsoft.com/en-us/kb/2207548
        http://www.sqlskills.com/blogs/glenn/windows-power-plan-effects-on-newer-intel-processors/

    .PARAMETER ComputerName
        Specifies the SQL Server host(s) where you want to test Windows Power Plan compliance. Accepts server names, IP addresses, or DbaInstance objects.
        Use this to audit power settings across your SQL Server environment, especially important for performance-critical instances where CPU throttling can impact query response times.

    .PARAMETER Credential
        Specifies a PSCredential object to use in authenticating to the server(s), instead of the current user account.

    .PARAMETER PowerPlan
        Specifies a custom power plan name to test against instead of the default "High Performance" plan. Use exact name matching as it appears in Windows Power Options.
        Useful when your organization has standardized on a specific custom power plan or when testing against plans like "Ultimate Performance" on Windows Server 2016+ or workstation operating systems.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: PowerPlan, OS, Utility
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaPowerPlan

    .OUTPUTS
        PSCustomObject

        Returns one object per computer tested with power plan compliance information.

        Default display properties (via Select-DefaultView):
        - ComputerName: The target computer name
        - ActivePowerPlan: Name of the currently active Windows Power Plan
        - RecommendedPowerPlan: Name of the recommended power plan (High Performance by default, or custom if -PowerPlan specified)
        - IsBestPractice: Boolean indicating if the active power plan matches the recommended plan

        Additional properties available:
        - ActiveInstanceId: UUID of the currently active power plan
        - RecommendedInstanceId: UUID of the recommended power plan
        - Credential: The PSCredential object used for authentication

        If the recommended power plan is not found on the system, RecommendedPowerPlan will contain an error message like "You do not have the high performance plan installed on this machine."

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
                if ($_.Exception -match "namespace") {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Unsupported operating system." -Continue -ErrorRecord $_ -Target $computer
                } elseif ($_.Exception -match "credentials are known to not work") {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Login failure for $($Credential.UserName)." -Continue -ErrorRecord $_ -Target $computer
                } else {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Check logs for more details." -Continue -ErrorRecord $_ -Target $computer
                }
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