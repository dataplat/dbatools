function Disable-DbaHideInstance {
    <#
    .SYNOPSIS
        Disables the Hide Instance setting of the SQL Server network configuration.

    .DESCRIPTION
        Disables the Hide Instance setting of the SQL Server network configuration.

        This requires access to the Windows Server and not the SQL Server instance. The setting is found in SQL Server Configuration Manager under the properties of SQL Server Network Configuration > Protocols for "InstanceName".

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
        Author: Gareth Newman (@gazeranco), ifexists.blog

        Website: https://dbatools.io
        Copyright: (c) 2019 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
         https://dbatools.io/Disable-DbaHideInstance

    .EXAMPLE
        PS C:\> Disable-DbaHideInstance

        Disables Hide Instance of SQL Engine on the default (MSSQLSERVER) instance on localhost. Requires (and checks for) RunAs admin.

    .EXAMPLE
        PS C:\> Disable-DbaHideInstance -SqlInstance sql01\SQL2008R2SP2

        Disables Hide Instance of SQL Engine for the SQL2008R2SP2 on sql01. Uses Windows Credentials to both connect and modify the registry.

    .EXAMPLE
        PS C:\> Disable-DbaHideInstance -SqlInstance sql01\SQL2008R2SP2 -WhatIf

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
                Set-ItemProperty -Path $regPath -Name HideInstance -Value $false
                $HideInstance = (Get-ItemProperty -Path $regPath -Name HideInstance).HideInstance

                [pscustomobject]@{
                    ComputerName = $env:COMPUTERNAME
                    InstanceName = $args[2]
                    SqlInstance  = $args[1]
                    HideInstance = ($HideInstance -eq $true)
                }
            }

            if ($PScmdlet.ShouldProcess("local", "Connecting to $instance to modify the HideInstance value in $regRoot for $($instance.InstanceName)")) {
                try {
                    Invoke-Command2 -ComputerName $resolved.FullComputerName -Credential $Credential -ArgumentList $regRoot, $vsname, $instanceName -ScriptBlock $scriptBlock -ErrorAction Stop
                    Write-Message -Level Critical -Message "HideInstance was successfully disabled on $($resolved.FullComputerName) for the $instanceName instance. The change takes effect immediately for new connections." -Target $instance
                } catch {
                    Stop-Function -Message "Failed to connect to $($resolved.FullComputerName) using PowerShell remoting" -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}