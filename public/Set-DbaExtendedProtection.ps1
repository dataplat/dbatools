function Set-DbaExtendedProtection {
    <#
    .SYNOPSIS
        Configures Extended Protection for Authentication on SQL Server network protocols

    .DESCRIPTION
        Modifies the Extended Protection registry setting for SQL Server network protocols to enhance connection security. Extended Protection helps prevent authentication relay attacks by requiring additional authentication at the network protocol level.

        This security feature is particularly useful in environments where you need to protect against man-in-the-middle attacks or when connecting over untrusted networks. When set to "Required", clients must support Extended Protection to connect, which may require updating older applications or connection strings.

        The function modifies Windows registry values directly and requires administrative privileges on the target server. Changes take effect immediately for new connections without requiring a SQL Server restart. This setting requires access to the Windows Server and not the SQL Server instance. The setting is found in SQL Server Configuration Manager under the properties of SQL Server Network Configuration > Protocols for "InstanceName".

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Allows you to login to the computer (not SQL Server instance) using alternative Windows credentials

    .PARAMETER Value
        Specifies the Extended Protection level for SQL Server network protocols. Accepts "Off", "Allowed", or "Required" (or equivalent integers 0, 1, 2).
        Use "Off" to disable Extended Protection, "Allowed" to accept both protected and unprotected connections, or "Required" to enforce Extended Protection for all client connections.
        Defaults to "Off" when not specified. Setting to "Required" may prevent older applications from connecting unless they support Extended Protection authentication.

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
        https://dbatools.io/Set-DbaExtendedProtection

    .EXAMPLE
        PS C:\> Set-DbaExtendedProtection

        Set Extended Protection of SQL Engine on the default (MSSQLSERVER) instance on localhost to "Off". Requires (and checks for) RunAs admin.

    .EXAMPLE
        PS C:\> Set-DbaExtendedProtection -Value Required

        Set Extended Protection of SQL Engine on the default (MSSQLSERVER) instance on localhost to "Required". Requires (and checks for) RunAs admin.

    .EXAMPLE
        PS C:\> Set-DbaExtendedProtection -SqlInstance sql01\SQL2008R2SP2

        Set Extended Protection of SQL Engine for the SQL2008R2SP2 on sql01 to "Off". Uses Windows Credentials to both connect and modify the registry.

    .EXAMPLE
        PS C:\> Set-DbaExtendedProtection -SqlInstance sql01\SQL2008R2SP2 -Value Allowed

        Set Extended Protection of SQL Engine for the SQL2008R2SP2 on sql01 to "Allowed". Uses Windows Credentials to both connect and modify the registry.

    .EXAMPLE
        PS C:\> Set-DbaExtendedProtection -SqlInstance sql01\SQL2008R2SP2 -WhatIf

        Shows what would happen if the command were executed.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low", DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [ValidateSet(0, "Off", 1, "Allowed", 2, "Required")]
        [object]$Value = "Off",
        [switch]$EnableException
    )
    begin {
        # Check value and set the integer value
        if (($Value -notin 0, 1, 2) -and ($null -ne $Value)) {
            $Value = switch ($Value) { "Off" { 0 } "Allowed" { 1 } "Required" { 2 } }
        }
    }
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
            Write-Message -Level Verbose -Message "ServiceAcct: $serviceaccount" -Target $instance
            Write-Message -Level Verbose -Message "InstanceName: $instancename" -Target $instance
            Write-Message -Level Verbose -Message "VSNAME: $vsname" -Target $instance
            Write-Message -Level Verbose -Message "Value: $Value" -Target $instance

            $scriptblock = {
                $regPath = "Registry::HKEY_LOCAL_MACHINE\$($args[0])\MSSQLServer\SuperSocketNetLib"
                Set-ItemProperty -Path $regPath -Name ExtendedProtection -Value $Value
                $extendedProtection = (Get-ItemProperty -Path $regPath -Name ExtendedProtection).ExtendedProtection

                [PSCustomObject]@{
                    ComputerName       = $env:COMPUTERNAME
                    InstanceName       = $args[2]
                    SqlInstance        = $args[1]
                    ExtendedProtection = "$extendedProtection - $(switch ($extendedProtection) { 0 { "Off" } 1 { "Allowed" } 2 { "Required" } })"
                }
            }
            if (Test-ShouldProcess -Context $PSCmdlet -Target "local" -Action "Connecting to $instance to modify the ExtendedProtection value in $regRoot for $($instance.InstanceName)") {
                try {
                    Invoke-Command2 -ComputerName $resolved.FullComputerName -Credential $Credential -ArgumentList $regRoot, $vsname, $instancename -ScriptBlock $scriptblock -ErrorAction Stop | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
                    Write-Message -Level Critical -Message "ExtendedProtection was successfully set on $($resolved.FullComputerName) for the $instancename instance. The change takes effect immediately for new connections." -Target $instance
                } catch {
                    Stop-Function -Message "Failed to connect to $($resolved.FullComputerName) using PowerShell remoting" -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}