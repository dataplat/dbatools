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

    .PARAMETER InputObject
        Enables piping from Get-DbaPowerPlan

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

    #>
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [PSCredential]$Credential,
        [Alias("CustomPowerPlan")]
        [string]$PowerPlan,
        [parameter(ValueFromPipeline)]
        [pscustomobject[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        $bpPowerPlan = [PSCustomObject]@{
            InstanceID = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            PowerPlan  = $null
        }

        # As we need all Power Plans per computer to have the active Power Plan and the best practice Power Plan,
        # we build a hash table with the computer name as key and the array of Power Plan objects from Get-DbaPowerPlan -List as value.
        $powerPlanHashTable = @{ }
        foreach ($computer in $ComputerName) {
            try {
                $powerPlanHashTable.$computer = Get-DbaPowerPlan -ComputerName $computer -Credential $Credential -List -EnableException
            } catch {
                Stop-Function -Message "Can't get Power Plan Info for $computer. Check logs for more details." -Continue -ErrorRecord $_ -Target $computer
            }
        }
    }

    process {
        # As piped input we accept output from Get-DbaPowerPlan -List with all the needed information,
        # Get-DbaPowerPlan with just the active Power Plan or just a computer name.
        # In the later two cases, we have to run Get-DbaPowerPlan -List to get the needed information.
        foreach ($object in $InputObject) {
            if ($null -ne $object.IsActive -and $null -ne $object.PowerPlan) {
                # We have an output from Get-DbaPowerPlan -List,
                # so we add that Power Plan to the array of Power Plans for that computer.
                # We have to initialize the array if it is the first Power Plan for this computer.
                $computer = $object.ComputerName
                if ($null -eq $powerPlanHashTable.$computer) {
                    $powerPlanHashTable.$computer = @( )
                }
                $powerPlanHashTable.$computer += $object
            } elseif ($null -ne $object.PowerPlan) {
                # We have an output from Get-DbaPowerPlan,
                # so we need to get all Power Plans with Get-DbaPowerPlan -List.
                $computer = $object.ComputerName
                try {
                    $powerPlanHashTable.$computer = Get-DbaPowerPlan -ComputerName $computer -Credential $object.Credential -List -EnableException
                } catch {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Check logs for more details." -Continue -ErrorRecord $_ -Target $computer
                }
            } else {
                $computer = $object
                try {
                    $powerPlanHashTable.$computer = Get-DbaPowerPlan -ComputerName $computer -Credential $Credential -List -EnableException
                } catch {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Check logs for more details." -Continue -ErrorRecord $_ -Target $computer
                }
            }
        }
    }

    end {
        foreach ($computer in $powerPlanHashTable.Keys) {
            $powerPlans = $powerPlanHashTable.$computer
            if ($CustomPowerPlan) {
                $bpPowerPlan.PowerPlan = $CustomPowerPlan
                $bpPowerPlan.InstanceID = ($powerPlans | Where-Object { $_.PowerPlan -eq $CustomPowerPlan }).InstanceID
                if ($null -eq $bpPowerplan.InstanceID) {
                    $bpPowerPlan.PowerPlan = "You do not have the Power Plan '$CustomPowerPlan' installed on this machine."
                }
            } else {
                $bpPowerPlan.PowerPlan = ($powerPlans | Where-Object { $_.InstanceID -eq $bpPowerPlan.InstanceID }).PowerPlan
                if ($null -eq $bpPowerplan.PowerPlan) {
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