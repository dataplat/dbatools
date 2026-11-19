function Enable-DbaForceNetworkEncryption {
    <#
    .SYNOPSIS
        Configures SQL Server to require encrypted connections from all clients by modifying the Windows registry

    .DESCRIPTION
        Modifies the Windows registry to force all client connections to SQL Server to use encryption, regardless of the client's encryption settings. This security feature ensures that all data transmitted between clients and SQL Server is encrypted, protecting against network eavesdropping and man-in-the-middle attacks.

        This function operates at the Windows level by updating the ForceEncryption registry value in the SQL Server network configuration, which normally requires manual changes through SQL Server Configuration Manager. The setting applies to all protocols and client connections to the specified instance.

        Important: You must restart the SQL Server service after running this command for the encryption requirement to take effect. Requires Windows administrator privileges on the target server, not SQL Server permissions.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Windows credentials for connecting to the remote computer to modify registry settings. Required when the current user lacks administrative access to the target server.
        This is used for Windows authentication to the computer, not SQL Server login credentials.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Encryption, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance where Force Encryption was enabled.

        Properties:
        - ComputerName: The name of the computer where the SQL Server instance is running
        - InstanceName: The SQL Server instance name (e.g., SQL2008R2SP2)
        - SqlInstance: The full SQL Server instance identifier (computer\instance format)
        - ForceEncryption: Boolean indicating whether Force Encryption was successfully enabled (will be $true on successful execution)
        - CertificateThumbprint: The thumbprint of the SSL certificate configured for the instance, or $null if no certificate is configured

    .LINK
        https://dbatools.io/Enable-DbaForceNetworkEncryption

    .EXAMPLE
        PS C:\> Enable-DbaForceNetworkEncryption

        Enables Force Encryption on the default (MSSQLSERVER) instance on localhost. Requires (and checks for) RunAs admin.

    .EXAMPLE
        PS C:\> Enable-DbaForceNetworkEncryption -SqlInstance sql01\SQL2008R2SP2

        Enables Force Network Encryption for the SQL2008R2SP2 on sql01. Uses Windows Credentials to both connect and modify the registry.

    .EXAMPLE
        PS C:\> Enable-DbaForceNetworkEncryption -SqlInstance sql01\SQL2008R2SP2 -WhatIf

        Shows what would happen if the command were executed.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low", DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {

        foreach ($instance in $SqlInstance) {
            Write-Message -Level VeryVerbose -Message "Processing $instance." -Target $instance
            $null = Test-ElevationRequirement -ComputerName $instance -Continue

            try {
                Write-Message -Level Verbose -Message "Resolving hostname."
                $resolved = $null
                $resolved = Resolve-DbaNetworkName -ComputerName $instance -Credential $Credential -EnableException
            } catch {
                $resolved = Resolve-DbaNetworkName -ComputerName $instance -Credential $Credential -Turbo
            }

            if ($null -eq $resolved) {
                Stop-Function -Message "Can't resolve $instance." -Target $instance -Continue -Category InvalidArgument
            }

            try {
                $sqlwmi = Invoke-ManagedComputerCommand -ComputerName $resolved.FullComputerName -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($($instance.InstanceName))"
            } catch {
                Stop-Function -Message "Failed to access $instance" -Target $instance -Continue -ErrorRecord $_
            }

            $regRoot = ($sqlwmi.AdvancedProperties | Where-Object Name -eq REGROOT).Value
            $vsname = ($sqlwmi.AdvancedProperties | Where-Object Name -eq VSNAME).Value
            try {
                $instanceName = $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(
            } catch {
                # Probably because the instance name has been aliased or does not exist or something
                # here to avoid an empty catch
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
                $cert = (Get-ItemProperty -Path $regPath -Name Certificate).Certificate
                #Variable marked as unused by PSScriptAnalyzer
                #$oldvalue = (Get-ItemProperty -Path $regPath -Name ForceEncryption).ForceEncryption
                Set-ItemProperty -Path $regPath -Name ForceEncryption -Value $true
                $forceencryption = (Get-ItemProperty -Path $regPath -Name ForceEncryption).ForceEncryption

                [PSCustomObject]@{
                    ComputerName          = $env:COMPUTERNAME
                    InstanceName          = $args[2]
                    SqlInstance           = $args[1]
                    ForceEncryption       = ($forceencryption -eq $true)
                    CertificateThumbprint = $cert
                }
            }

            if ($PScmdlet.ShouldProcess("local", "Connecting to $instance to modify the ForceEncryption value in $regRoot for $($instance.InstanceName)")) {
                try {
                    Invoke-Command2 -ComputerName $resolved.FullComputerName -Credential $Credential -ArgumentList $regRoot, $vsname, $instanceName -ScriptBlock $scriptBlock -ErrorAction Stop | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
                    Write-Message -Level Critical -Message "Force encryption was successfully set on $($resolved.FullComputerName) for the $instanceName instance. You must now restart the SQL Server for changes to take effect." -Target $instance
                } catch {
                    Stop-Function -Message "Failed to connect to $($resolved.FullComputerName) using PowerShell remoting" -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}