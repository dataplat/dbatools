function Enable-DbaAgHadr {
    <#
    .SYNOPSIS
        Enables HADR service setting on SQL Server instances to allow Availability Group creation.

    .DESCRIPTION
        Configures the High Availability Disaster Recovery (HADR) service setting on SQL Server instances, which is a required prerequisite before you can create Availability Groups. This setting must be enabled at the instance level and requires a service restart to take effect. Use this command when preparing SQL Server instances for Availability Group participation after your Windows Server Failover Cluster is already configured.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Windows credential object used to connect to the target server with different authentication context.
        Required when the current user lacks administrative privileges on the SQL Server host or when connecting across domain boundaries.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Automatically restarts the SQL Server Database Engine and SQL Server Agent services to immediately apply the HADR setting change.
        Without this parameter, the HADR setting change requires a manual service restart before Availability Groups can be created.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Enable-DbaAgHadr

    .EXAMPLE
        PS C:\> Enable-DbaAgHadr -SqlInstance sql2016

        Sets Hadr service to enabled for the instance sql2016 but changes will not be applied until the next time the server restarts.

    .EXAMPLE
        PS C:\> Enable-DbaAgHadr -SqlInstance sql2016 -Force

        Sets Hadr service to enabled for the instance sql2016, and restart the service to apply the change.

    .EXAMPLE
        PS C:\> Enable-DbaAgHadr -SqlInstance sql2012\dev1 -Force

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
            if ($isHadrEnabled) {
                Write-Message -Level Warning -Message "Hadr is already enabled for instance: $($instance.FullName)"
                $noChange = $true
                continue
            }
            #>

            $scriptBlock = {
                $instance = $args[0]
                $sqlService = $wmi.Services | Where-Object DisplayName -eq "SQL Server ($instance)"
                $sqlService.ChangeHadrServiceSetting(1)
            }

            if ($noChange -eq $false) {
                if ($PSCmdlet.ShouldProcess($instance, "Changing Hadr from $isHadrEnabled to 1 for $instance")) {
                    try {
                        Invoke-ManagedComputerCommand -ComputerName $computerFullName -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $instanceName
                    } catch {
                        Stop-Function -Continue -Message "Failure on $($instance.FullName) | This may be because AlwaysOn Availability Groups feature requires the x86(non-WOW) or x64 Enterprise Edition of SQL Server 2012 (or later version) running on Windows Server 2008 (or later version) with WSFC hotfix KB 2494036 installed."
                    }
                }
            }

            if (Test-Bound -ParameterName Force) {
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
                IsHadrEnabled = $true
            }
        }
    }
}