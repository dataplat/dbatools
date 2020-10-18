function Get-DbaPowerPlan {
    <#
    .SYNOPSIS
        Gets the Power Plan settings for compliance with best practices, which recommend High Performance for SQL Server.

    .DESCRIPTION
        Gets the Power Plan settings on a computer against best practices recommendations.

    .PARAMETER ComputerName
        The server(s) to check Power Plan settings on.

    .PARAMETER Credential
        Specifies a PSCredential object to use in authenticating to the server(s), instead of the current user account.

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
        https://dbatools.io/Get-DbaPowerPlan

    .EXAMPLE
        PS C:\> Get-DbaPowerPlan -ComputerName sql2017

        Gets the Power Plan settings for sql2017

    .EXAMPLE
        PS C:\> Get-DbaPowerPlan -ComputerName sql2017 -Credential ad\admin

        Gets the Power Plan settings for sql2017 using an alternative credential

    #>
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    process {
        foreach ($computer in $ComputerName) {
            $null = Test-ElevationRequirement -ComputerName $computer -Continue

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

            [PSCustomObject]@{
                ComputerName = $computer
                InstanceId   = $powerPlan.InstanceID
                PowerPlan    = $powerPlan.ElementName
                Credential   = $Credential
            } | Select-DefaultView -ExcludeProperty Credential, InstanceId
        }
    }
}