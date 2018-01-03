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

        .PARAMETER Detailed
             Output all properties, will be deprecated in 1.0.0 release.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: PowerPlan
            Requires: WMI access to servers

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Test-DbaPowerPlan

        .EXAMPLE
            Test-DbaPowerPlan -ComputerName sqlserver2014a

            Checks the Power Plan settings for sqlserver2014a and indicates whether or not it complies with best practices.

        .EXAMPLE
            Test-DbaPowerPlan -ComputerName sqlserver2014a -CustomPowerPlan 'Maximum Performance'

            Checks the Power Plan settings for sqlserver2014a and indicates whether or not it is set to the custom plan "Maximum Performance".
    #>
    param (
        [parameter(ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer", "SqlInstance")]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string]$CustomPowerPlan,
        [switch]$Detailed,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed

        $bpPowerPlan = [PSCustomObject]@{
            InstanceID  = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            ElementName = $null
        }

        $sessionOption = New-CimSessionOption -Protocol DCom
    }

    process {
        foreach ($computer in $ComputerName) {
            $server = Resolve-DbaNetworkName -ComputerName $computer -Credential $credential

            $computerResolved = $server.FullComputerName

            if (!$computerResolved) {
                Stop-Function -Message "Couldn't resolve hostname. Skipping." -Continue
            }

            Write-Message -Level Verbose -Message "Creating CimSession on $computer over WSMan."

            if (!$Credential) {
                $cimSession = New-CimSession -ComputerName $computerResolved -ErrorAction SilentlyContinue
            }
            else {
                $cimSession = New-CimSession -ComputerName $computerResolved -ErrorAction SilentlyContinue -Credential $Credential
            }

            if ($null -eq $cimSession.id) {
                Write-Message -Level Verbose -Message "Creating CimSession on $computer over WSMan failed. Creating CimSession on $computer over DCOM."

                if (!$Credential) {
                    $cimSession = New-CimSession -ComputerName $computerResolved -SessionOption $sessionOption -ErrorAction SilentlyContinue -Credential $Credential
                }
                else {
                    $cimSession = New-CimSession -ComputerName $computerResolved -SessionOption $sessionOption -ErrorAction SilentlyContinue
                }
            }

            if ($null -eq $cimSession.id) {
                Stop-Function -Message "Can't create CimSession on $computer." -Target $computer
            }

            Write-Message -Level Verbose -Message "Getting Power Plan information from $computer."

            try {
                $powerPlans = Get-CimInstance -CimSession $cimSession -ClassName Win32_PowerPlan -Namespace "root\cimv2\power" -ErrorAction Stop | Select-Object ElementName, InstanceID, IsActive
            }
            catch {
                if ($_.Exception -match "namespace") {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Unsupported operating system." -Continue -ErrorRecord $_ -Target $computer
                }
                else {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Check logs for more details." -Continue -ErrorRecord $_ -Target $computer
                }
            }

            $powerPlan = $powerPlans | Where-Object IsActive -eq 'True' | Select-Object ElementName, InstanceID
            $powerPlan.InstanceID = $powerPlan.InstanceID.Split('{')[1].Split('}')[0]

            if ($CustomPowerPlan.Length -gt 0) {
                $bpPowerPlan.ElementName = $CustomPowerPlan
                $bpPowerPlan.InstanceID = $($powerPlans | Where-Object { $_.ElementName -eq $CustomPowerPlan }).InstanceID
            }
            else {
                $bpPowerPlan.ElementName = $($powerPlans | Where-Object { $_.InstanceID.Split('{')[1].Split('}')[0] -eq $bpPowerPlan.InstanceID }).ElementName
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
            }
            else {
                $isBestPractice = $false
            }

            [PSCustomObject]@{
                ComputerName         = $computer
                ActivePowerPlan      = $powerPlan.ElementName
                RecommendedPowerPlan = $bpPowerPlan.ElementName
                isBestPractice       = $isBestPractice
            }
        }
    }
}