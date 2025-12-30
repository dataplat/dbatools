function Disable-DbaAgHadr {
    <#
    .SYNOPSIS
        Disables High Availability Disaster Recovery (HADR) capability on SQL Server instances.

    .DESCRIPTION
        Disables the HADR service setting at the SQL Server instance level, effectively removing the instance's ability to participate in Availability Groups. This is commonly needed when decommissioning servers from AGs, troubleshooting AG setup issues, or converting instances back to standalone operation after removing them from Availability Groups.

        The function modifies the HADR setting through WMI but requires a SQL Server service restart to take effect. Use the -Force parameter to automatically restart both SQL Server and SQL Agent services immediately, or manually restart later to apply the change.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Windows server as a different user

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Automatically restarts both SQL Server and SQL Server Agent services to immediately apply the HADR setting change. Without this switch, the HADR disable setting is changed but requires manual service restart to take effect.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per successfully processed instance, containing the following properties:

        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The name of the SQL Server instance (e.g., MSSQLSERVER or named instance)
        - SqlInstance: The full SQL Server instance identifier in the format ComputerName\InstanceName
        - IsHadrEnabled: Boolean value indicating the HADR status (always $false for successful disable operations)

    .NOTES
        Tags: AG, HA
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Disable-DbaAgHadr

    .EXAMPLE
        PS C:\> Disable-DbaAgHadr -SqlInstance sql2016

        Sets Hadr service to disabled for the instance sql2016 but changes will not be applied until the next time the server restarts.

    .EXAMPLE
        PS C:\> Disable-DbaAgHadr -SqlInstance sql2016 -Force

        Sets Hadr service to disabled for the instance sql2016, and restart the service to apply the change.

    .EXAMPLE
        PS C:\> Disable-DbaAgHadr -SqlInstance sql2012\dev1 -Force

        Sets Hadr service to disabled for the instance dev1 on sq2012, and restart the service to apply the change.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $computer = $computerFullName = $instance.ComputerName
            $instanceName = $instance.InstanceName
            if (-not (Test-ElevationRequirement -ComputerName $instance)) {
                return
            }
            $noChange = $false

            <#
            #Variable marked as unused by PSScriptAnalyzer
            switch ($instance.InstanceName) {
                'MSSQLSERVER' { $agentName = 'SQLSERVERAGENT' }
                default { $agentName = "SQLAgent`$$instanceName" }
            }
            #>

            try {
                Write-Message -Level Verbose -Message "Checking current Hadr setting for $computer"
                $currentState = Get-WmiHadr -SqlInstance $instance -Credential $Credential
            } catch {
                Stop-Function -Message "Failure to pull current state of Hadr setting on $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $isHadrEnabled = $currentState.IsHadrEnabled
            Write-Message -Level InternalComment -Message "$instance Hadr current value: $isHadrEnabled"

            # hadr results from sql wmi can be iffy, skip the check
            <#
            if (-not $isHadrEnabled) {
                Write-Message -Level Warning -Message "Hadr is already disabled for instance: $($instance.FullName)"
                $noChange = $true
                continue
            }
            #>

            $scriptBlock = {
                $instance = $args[0]
                $sqlService = $wmi.Services | Where-Object DisplayName -eq "SQL Server ($instance)"
                $sqlService.ChangeHadrServiceSetting(0)
            }

            if ($noChange -eq $false) {
                if ($PSCmdlet.ShouldProcess($instance, "Changing Hadr from $isHadrEnabled to 0 for $instance")) {
                    try {
                        Invoke-ManagedComputerCommand -ComputerName $computerFullName -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $instanceName
                    } catch {
                        Stop-Function -Continue -Message "Failure on $($instance.FullName) | This may be because AlwaysOn Availability Groups feature requires the x86(non-WOW) or x64 Enterprise Edition of SQL Server 2012 (or later version) running on Windows Server 2008 (or later version) with WSFC hotfix KB 2494036 installed."
                    }
                }
                if (Test-Bound 'Force') {
                    if ($PSCmdlet.ShouldProcess($instance, "Force provided, restarting Engine and Agent service for $instance on $computerFullName")) {
                        try {
                            $null = Stop-DbaService -ComputerName $computerFullName -InstanceName $instanceName -Type Agent, Engine
                            $null = Start-DbaService -ComputerName $computerFullName -InstanceName $instanceName -Type Agent, Engine
                        } catch {
                            Stop-Function -Message "Issue restarting $instance" -Target $instance -Continue
                        }
                    }
                }
                $newState = Get-WmiHadr -SqlInstance $instance -Credential $Credential

                if (Test-Bound -Not -ParameterName Force) {
                    Write-Message -Level Warning -Message "You must restart the SQL Server for it to take effect."
                }

                [PSCustomObject]@{
                    ComputerName  = $newState.ComputerName
                    InstanceName  = $newState.InstanceName
                    SqlInstance   = $newState.SqlInstance
                    IsHadrEnabled = $false
                }
            }
        }
    }
}