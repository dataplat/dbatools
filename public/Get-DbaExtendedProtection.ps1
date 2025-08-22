function Get-DbaExtendedProtection {
    <#
    .SYNOPSIS
        Retrieves Extended Protection authentication settings from SQL Server network configuration.

    .DESCRIPTION
        Retrieves the Extended Protection setting for SQL Server instances to help assess authentication security posture. Extended Protection is a Windows authentication enhancement that helps prevent credential relay attacks by validating channel binding and service principal names.

        This function queries the Windows registry directly rather than connecting to SQL Server, so it requires Windows-level access to the target server. The setting corresponds to what you see in SQL Server Configuration Manager under Network Configuration > Protocols properties, but can be checked programmatically across multiple instances for compliance auditing.

        Returns the current setting as both a numeric value (0, 1, 2) and descriptive text (Off, Allowed, Required) to help DBAs understand the security configuration and plan any necessary changes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Allows you to login to the computer (not SQL Server instance) using alternative Windows credentials

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, Security
        Author: Claudio Silva (@claudioessilva), claudioessilva.eu

        Website: https://dbatools.io
        Copyright: (c) 2019 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaExtendedProtection

    .EXAMPLE
        PS C:\> Get-DbaExtendedProtection

        Gets Extended Protection on the default (MSSQLSERVER) instance on localhost - requires (and checks for) RunAs admin.

    .EXAMPLE
        PS C:\> Get-DbaExtendedProtection -SqlInstance sql01\SQL2008R2SP2

        Set Extended Protection of SQL Engine for the SQL2008R2SP2 on sql01 to "Off". Uses Windows Credentials to both connect and modify the registry.
        Gets Extended Protection for the SQL2008R2SP2 on sql01. Uses Windows Credentials to both login and view the registry.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low", DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {

        foreach ($instance in $SqlInstance) {
            Write-Message -Level VeryVerbose -Message "Processing $instance." -Target $instance
            if ($instance.IsLocalHost) {
                $null = Test-ElevationRequirement -ComputerName $instance -Continue
            }

            try {
                $resolved = Resolve-DbaNetworkName -ComputerName $instance -Credential $Credential -EnableException
            } catch {
                try {
                    $resolved = Resolve-DbaNetworkName -ComputerName $instance -Credential $Credential -Turbo -EnableException
                } catch {
                    Stop-Function -Message "Issue resolving $instance" -Target $instance -Category InvalidArgument -Continue
                }
            }

            try {
                $sqlwmi = Invoke-ManagedComputerCommand -ComputerName $resolved.FullComputerName -ScriptBlock { $wmi.Services } -Credential $Credential -EnableException | Where-Object DisplayName -eq "SQL Server ($($instance.InstanceName))"
            } catch {
                Stop-Function -Message "Failed to access $instance" -Target $instance -Continue -ErrorRecord $_
            }

            $regRoot = ($sqlwmi.AdvancedProperties | Where-Object Name -eq REGROOT).Value
            $vsname = ($sqlwmi.AdvancedProperties | Where-Object Name -eq VSNAME).Value
            try {
                $instanceName = $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '')
            } catch {
                $null = 1
            }
            $serviceAccount = $sqlwmi.ServiceAccount

            if ([System.String]::IsNullOrEmpty($regRoot)) {
                $regRoot = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                $vsname = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }

                if (![System.String]::IsNullOrEmpty($regRoot)) {
                    $regRoot = ($regRoot -Split 'Value\=')[1]
                    $vsname = ($vsname -Split 'Value\=')[1]
                } else {
                    Stop-Function -Message "Can't find instance $vsname on $instance." -Continue -Category ObjectNotFound -Target $instance
                }
            }

            if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $instance }

            Write-Message -Level Verbose -Message "Regroot: $regRoot" -Target $instance
            Write-Message -Level Verbose -Message "ServiceAcct: $serviceAccount" -Target $instance
            Write-Message -Level Verbose -Message "InstanceName: $instanceName" -Target $instance
            Write-Message -Level Verbose -Message "VSNAME: $vsname" -Target $instance

            $scriptblock = {
                $regPath = "Registry::HKEY_LOCAL_MACHINE\$($args[0])\MSSQLServer\SuperSocketNetLib"
                $extendedProtection = (Get-ItemProperty -Path $regPath -Name ExtendedProtection).ExtendedProtection

                [PSCustomObject]@{
                    ComputerName       = $env:COMPUTERNAME
                    InstanceName       = $args[2]
                    SqlInstance        = $args[1]
                    ExtendedProtection = "$extendedProtection - $(switch ($extendedProtection) { 0 { "Off" } 1 { "Allowed" } 2 { "Required" } })"
                }
            }

            if ($PScmdlet.ShouldProcess("local", "Connecting to $instance to modify the ExtendedProtection value in $regRoot for $($instance.InstanceName)")) {
                try {
                    Invoke-Command2 -ComputerName $resolved.FullComputerName -Credential $Credential -ArgumentList $regRoot, $vsname, $instanceName -ScriptBlock $scriptblock -ErrorAction Stop | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
                } catch {
                    Stop-Function -Message "Failed to connect to $($resolved.FullComputerName) using PowerShell remoting" -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}