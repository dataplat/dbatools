function Enable-DbaHideInstance {
    <#
    .SYNOPSIS
        Enables the Hide Instance setting to prevent SQL Server Browser service from advertising the instance.

    .DESCRIPTION
        Enables the Hide Instance setting in the SQL Server network configuration registry, which prevents the instance from responding to SQL Server Browser service enumeration requests. This security setting makes the instance invisible to network discovery tools and requires clients to specify the exact port number or use a SQL Server alias to connect.

        The function modifies the HideInstance registry value in HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Microsoft SQL Server\[InstanceName]\MSSQLServer\SuperSocketNetLib. This is commonly used in security-hardened environments to reduce the attack surface by hiding instance details from network scanning tools.

        This setting requires Windows administrative access to modify the registry and does not require SQL Server permissions. The change takes effect immediately for new connections, but existing connections remain unaffected.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances where you want to enable the Hide Instance setting.
        This parameter accepts server names, server\instance combinations, or fully qualified domain names.
        When not specified, defaults to the local computer's default instance (MSSQLSERVER).

    .PARAMETER Credential
        Windows credentials used to connect to the target computer and modify the registry settings.
        This is required when running against remote servers where your current Windows account lacks administrative access.
        Note that this connects to the Windows computer, not the SQL Server instance itself.

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
        Author: Gareth Newman (@gazeranco), ifexists.blog

        Website: https://dbatools.io
        Copyright: (c) 2019 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Enable-DbaHideInstance

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance processed, with information about the Hide Instance setting change.

        Properties:
        - ComputerName: The name of the computer where the registry change was made
        - InstanceName: The SQL Server instance name (e.g., MSSQLSERVER, SQL2008R2SP2)
        - SqlInstance: The full SQL Server instance identifier (computer\instance format)
        - HideInstance: Boolean indicating whether the Hide Instance setting was successfully enabled (true) or not (false)

    .EXAMPLE
        PS C:\> Enable-DbaHideInstance

        Enables Hide Instance of SQL Engine on the default (MSSQLSERVER) instance on localhost. Requires (and checks for) RunAs admin.

    .EXAMPLE
        PS C:\> Enable-DbaHideInstance -SqlInstance sql01\SQL2008R2SP2

        Enables Hide Instance of SQL Engine for the SQL2008R2SP2 on sql01. Uses Windows Credentials to both connect and modify the registry.

    .EXAMPLE
        PS C:\> Enable-DbaHideInstance -SqlInstance sql01\SQL2008R2SP2 -WhatIf

        Shows what would happen if the command were executed.

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

            $scriptBlock = {
                $regPath = "Registry::HKEY_LOCAL_MACHINE\$($args[0])\MSSQLServer\SuperSocketNetLib"
                Set-ItemProperty -Path $regPath -Name HideInstance -Value $true
                $hideInstance = (Get-ItemProperty -Path $regPath -Name HideInstance).HideInstance

                [PSCustomObject]@{
                    ComputerName = $env:COMPUTERNAME
                    InstanceName = $args[2]
                    SqlInstance  = $args[1]
                    HideInstance = ($hideInstance -eq $true)
                }
            }

            if ($PScmdlet.ShouldProcess("local", "Connecting to $instance to modify the HideInstance value in $regRoot for $($instance.InstanceName)")) {
                try {
                    Invoke-Command2 -ComputerName $resolved.FullComputerName -Credential $Credential -ArgumentList $regRoot, $vsname, $instanceName -ScriptBlock $scriptBlock -ErrorAction Stop | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
                    Write-Message -Level Critical -Message "HideInstance was successfully set on $($resolved.FullComputerName) for the $instanceName instance. The change takes effect immediately for new connections." -Target $instance
                } catch {
                    Stop-Function -Message "Failed to connect to $($resolved.FullComputerName) using PowerShell remoting" -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}