function Get-DbaPowerPlan {
    <#
    .SYNOPSIS
        Retrieves Windows Power Plan configuration from SQL Server hosts to verify High Performance settings.

    .DESCRIPTION
        Checks the active Windows Power Plan configuration on SQL Server host computers to ensure they follow performance best practices. SQL Server performance can be significantly impacted by power management settings that throttle CPU frequency or put processors to sleep during idle periods.

        By default, returns the currently active power plan for each specified computer. Use the -List parameter to view all available power plans and their status. Microsoft recommends using the "High Performance" power plan for SQL Server hosts to prevent CPU throttling and ensure consistent database performance.

    .PARAMETER ComputerName
        Specifies the SQL Server host computer(s) to check for Windows Power Plan configuration. Accepts multiple server names for bulk power plan auditing.
        Use this to verify that your SQL Server hosts are configured with the recommended "High Performance" power plan instead of "Balanced" or "Power Saver" modes that can throttle CPU performance.

    .PARAMETER Credential
        Specifies a PSCredential object to use in authenticating to the server(s), instead of the current user account.

    .PARAMETER List
        Returns all available power plans on the target computers instead of just the currently active plan. Shows the status of each plan including which one is active.
        Use this when you need to see all power plan options available on a server before making configuration changes or to audit power plan availability across your environment.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: PowerPlan, Utility
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPowerPlan

    .OUTPUTS
        PSCustomObject

        Default output (when -List is not specified):

        Returns one object per computer queried, showing the currently active power plan.

        Properties:
        - ComputerName: The SQL Server host computer name
        - PowerPlan: Name of the currently active power plan (e.g., "High Performance", "Balanced", "Power saver"); shows "Unknown" if detection fails

        When -List is specified:

        Returns one object per available power plan on each computer, showing all power plans and which one is active.

        Properties:
        - ComputerName: The SQL Server host computer name
        - PowerPlan: Name of the power plan
        - IsActive: Boolean indicating if this power plan is currently active (True or False)

    .EXAMPLE
        PS C:\> Get-DbaPowerPlan -ComputerName sql2017

        Gets the Power Plan settings for sql2017

    .EXAMPLE
        PS C:\> Get-DbaPowerPlan -ComputerName sql2017 -Credential ad\admin

        Gets the Power Plan settings for sql2017 using an alternative credential

    .EXAMPLE
        PS C:\> Get-DbaPowerPlan -ComputerName sql2017 -List

        Gets all available Power Plans on sql2017

    #>
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$ComputerName,
        [PSCredential]$Credential,
        [switch]$List,
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
                } elseif ($_.Exception -match "credentials are known to not work") {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Login failure for $($Credential.UserName)." -Continue -ErrorRecord $_ -Target $computer
                } else {
                    Stop-Function -Message "Can't get Power Plan Info for $computer. Check logs for more details." -Continue -ErrorRecord $_ -Target $computer
                }
            }

            if ($List) {
                foreach ($powerPlan in $powerPlans) {
                    $powerPlan.InstanceID = $powerPlan.InstanceID.Split('{')[1].Split('}')[0]
                    [PSCustomObject]@{
                        ComputerName = $computer
                        InstanceId   = $powerPlan.InstanceID
                        PowerPlan    = $powerPlan.ElementName
                        IsActive     = $powerPlan.IsActive
                        Credential   = $Credential
                    } | Select-DefaultView -Property ComputerName, PowerPlan, IsActive
                }
            } else {
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
                } | Select-DefaultView -Property ComputerName, PowerPlan
            }
        }
    }
}