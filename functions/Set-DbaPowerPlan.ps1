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
            Requires: WMI access to servers

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Set-DbaPowerPlan

        .EXAMPLE
            Set-DbaPowerPlan -ComputerName sqlserver2014a

            Sets the Power Plan to High Performance. Skips it if its already set.

        .EXAMPLE
            Set-DbaPowerPlan -ComputerName sqlcluster -CustomPowerPlan 'Maximum Performance'

            Sets the Power Plan to the custom power plan called "Maximum Performance". Skips it if its already set.

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer", "SqlInstance")]
        [object[]]$ComputerName,
        [ValidateSet('High Performance', 'Balanced', 'Power saver')]
        [string]$PowerPlan = 'High Performance',
        [string]$CustomPowerPlan,
        [switch][Alias('Silent')]
        $EnableException
    )

    begin {
        if ($CustomPowerPlan.Length -gt 0) {
            $PowerPlan = $CustomPowerPlan
        }

        function Set-DbaPowerPlanInternal {
            param($server)

            try {
                Write-Message -Level Verbose -Message "Testing connection to $server and resolving IP address."
                $ipaddr = (Test-Connection $server -Count 1 -ErrorAction SilentlyContinue).Ipv4Address | Select-Object -First 1

            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $server
                return
            }

            try {
                Write-Message -Level Verbose -Message "Getting Power Plan information from $server."
                $query = "Select ElementName from Win32_PowerPlan WHERE IsActive = 'true'"
                $currentplan = Get-WmiObject -Namespace Root\CIMV2\Power -ComputerName $ipaddr -Query $query -ErrorAction SilentlyContinue
                $currentplan = $currentplan.ElementName
            }
            catch {
                Stop-Function -Message "Can't connect to WMI on $server." -Category ConnectionError -ErrorRecord $_ -Target $server
                return
            }

            if ($null -eq $currentplan) {
                # the try/catch above isn't working, so make it silent and handle it here.
                Stop-Function -Message "Cannot get Power Plan for $server." -Category ConnectionError -ErrorRecord $_ -Target $server
                return
            }

            $planinfo = [PSCustomObject]@{
                Server            = $server
                PreviousPowerPlan = $currentplan
                ActivePowerPlan   = $PowerPlan
            }

            if ($PowerPlan -ne $currentplan) {
                if ($Pscmdlet.ShouldProcess($server, "Changing Power Plan from $CurrentPlan to $PowerPlan")) {
                    try {
                        Write-Message -Level Verbose -Message "Setting Power Plan to $PowerPlan."
                        $null = (Get-WmiObject -Name root\cimv2\power -ComputerName $ipaddr -Class Win32_PowerPlan -Filter "ElementName='$PowerPlan'").Activate()
                    }
                    catch {
                        Stop-Function -Message "Couldn't set Power Plan on $server." -Category ConnectionError -ErrorRecord $_ -Target $server
                        return
                    }
                }
            }
            else {
                if ($Pscmdlet.ShouldProcess($server, "Stating power plan is already set to $PowerPlan, won't change.")) {
                    Write-Message -Level Verbose -Message "PowerPlan on $server is already set to $PowerPlan. Skipping."
                }
            }

            return $planinfo
        }


        $collection = New-Object System.Collections.ArrayList
        $processed = New-Object System.Collections.ArrayList
    }

    process {
        foreach ($server in $ComputerName) {
            if ($server -match 'Server\=') {
                Write-Message -Level Verbose -Message "Matched that value was piped from Test-DbaPowerPlan."
                # I couldn't properly unwrap the output from  Test-DbaPowerPlan so here goes.
                $lol = $server.Split("\;")[0]
                $lol = $lol.TrimEnd("\}")
                $lol = $lol.TrimStart("\@\{Server")
                # There was some kind of parsing bug here, don't clown
                $server = $lol.TrimStart("\=")
            }

            if ($server -match '\\') {
                $server = $server.Split('\\')[0]
            }

            if ($server -notin $processed) {
                $null = $processed.Add($server)
                Write-Message -Level Verbose -Message "Connecting to $server."
            }
            else {
                continue
            }

            $data = Set-DbaPowerPlanInternal $server

            if ($data.Count -gt 1) {
                $data.GetEnumerator() | ForEach-Object { $null = $collection.Add($_) }
            }
            else {
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
