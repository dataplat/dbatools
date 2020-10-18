function Test-DbaPowerPlan {
    <#
    .SYNOPSIS
        Checks the Power Plan settings for compliance with best practices, which recommend High Performance for SQL Server.

    .DESCRIPTION
        Checks the Power Plan settings on a computer against best practices recommendations. If one server is checked, only $true or $false is returned. If multiple servers are checked, each server's name and an isBestPractice field are returned.

        References:
        https://support.microsoft.com/en-us/kb/2207548
        http://www.sqlskills.com/blogs/glenn/windows-power-plan-effects-on-newer-intel-processors/

    .PARAMETER ComputerName
        The server(s) to check Power Plan settings on.

    .PARAMETER Credential
        Specifies a PSCredential object to use in authenticating to the server(s), instead of the current user account.

    .PARAMETER CustomPowerPlan
        If your organization uses a custom power plan that's considered best practice, specify it here.

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
        PS C:\> Test-DbaPowerPlan -ComputerName sqlserver2014a -CustomPowerPlan 'Maximum Performance'

        Checks the Power Plan settings for sqlserver2014a and indicates whether or not it is set to the custom plan "Maximum Performance".

    #>
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string]$CustomPowerPlan,
        [parameter(ValueFromPipeline)]
        [pscustomobject[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        $bpPowerPlan = [PSCustomObject]@{
            InstanceID  = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            ElementName = $null
        }
    }

    process {
        if (Test-Bound -ParameterName ComputerName) {
            $InputObject += Get-DbaPowerPlan -ComputerName $ComputerName -Credential $Credential
        }

        foreach ($powerPlan in $InputObject) {
            $computer = $powerPlan.ComputerName
            $Credential = $powerPlan.Credential

            $server = Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential

            $computerResolved = $server.FullComputerName

            if (-not $computerResolved) {
                Stop-Function -Message "Couldn't resolve hostname. Skipping." -Continue
            }

            $splatDbaCmObject = @{
                ComputerName    = $computerResolved
                EnableException = $true
            }

            if (Test-Bound "Credential") {
                $splatDbaCmObject["Credential"] = $Credential
            }

            Write-Message -Level Verbose -Message "Getting Power Plan information from $computer."

            try {
                $powerPlans = Get-DbaCmObject @splatDbaCmObject -ClassName Win32_PowerPlan -Namespace "root\cimv2\power" | Select-Object ElementName, InstanceId, IsActive
            } catch {
                if ($_.Exception -match "namespace") {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Unsupported operating system." -Continue -ErrorRecord $_ -Target $computer
                } else {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Check logs for more details." -Continue -ErrorRecord $_ -Target $computer
                }
            }

            $powerPlan = $powerPlans | Where-Object IsActive -eq 'True' | Select-Object ElementName, InstanceID
            $powerPlan.InstanceID = $powerPlan.InstanceID.Split('{')[1].Split('}')[0]

            if ($null -eq $powerPlan.InstanceID) {
                $powerPlan.ElementName = "Unknown"
            }
            if ($CustomPowerPlan) {
                $bpPowerPlan.ElementName = $CustomPowerPlan
                $bpPowerPlan.InstanceID = $($powerPlans | Where-Object {
                        $_.ElementName -eq $CustomPowerPlan
                    }).InstanceID
            } else {
                $bpPowerPlan.ElementName = $($powerPlans | Where-Object {
                        $_.InstanceID.Split('{')[1].Split('}')[0] -eq $bpPowerPlan.InstanceID
                    }).ElementName
                if ($null -eq $bpPowerplan.ElementName) {
                    $bpPowerPlan.ElementName = "You do not have the high performance plan installed on this machine."
                }
            }

            Write-Message -Level Verbose -Message "Recommended GUID is $($bpPowerPlan.InstanceID) and you have $($powerPlan.InstanceID)."

            if ($null -eq $powerPlan.InstanceID) {
                $powerPlan.ElementName = "Unknown"
            }

            if ($powerPlan.InstanceID -eq $bpPowerPlan.InstanceID) {
                $isBestPractice = $true
            } else {
                $isBestPractice = $false
            }

            [PSCustomObject]@{
                ComputerName         = $computer
                ActivePowerPlan      = $powerPlan.ElementName
                RecommendedPowerPlan = $bpPowerPlan.ElementName
                isBestPractice       = $isBestPractice
                Credential           = $Credential
            } | Select-DefaultView -ExcludeProperty Credential
        }
    }
}