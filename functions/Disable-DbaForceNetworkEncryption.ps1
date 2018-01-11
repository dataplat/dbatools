#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Disable-DbaForceNetworkEncryption {
    <#
        .SYNOPSIS
            Disables Force Encryption for a SQL Server instance

        .DESCRIPTION
            Disables Force Encryption for a SQL Server instance. Note that this requires access to the Windows Server, not the SQL instance itself.

            This setting is found in Configuration Manager.

        .PARAMETER SqlInstance
            The target SQL Server. Defaults to localhost.

        .PARAMETER Credential
            Allows you to login to the computer (not SQL Server instance) using alternative Windows credentials.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .EXAMPLE
            Disable-DbaForceNetworkEncryption

            Disables Force Encryption on the default (MSSQLSERVER) instance on localhost - requires (and checks for) RunAs admin.

        .EXAMPLE
            Disable-DbaForceNetworkEncryption -SqlInstance sql01\SQL2008R2SP2

            Disables Force Network Encryption for the SQL2008R2SP2 on sql01. Uses Windows Credentials to both login and modify the registry.

        .EXAMPLE
            Disable-DbaForceNetworkEncryption -SqlInstance sql01\SQL2008R2SP2 -WhatIf

            Shows what would happen if the command were executed.

        .NOTES
            Tags: Certificate

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer", "ComputerName")]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch][Alias('Silent')]$EnableException
    )
    process {

        foreach ($instance in $sqlinstance) {
            Write-Message -Level VeryVerbose -Message "Processing $instance." -Target $instance
            $null = Test-ElevationRequirement -ComputerName $instance -Continue

            Write-Message -Level Verbose -Message "Resolving hostname."
            $resolved = $null
            $resolved = Resolve-DbaNetworkName -ComputerName $instance -Turbo

            if ($null -eq $resolved) {
                Stop-Function -Message "Can't resolve $instance." -Target $instance -Continue -Category InvalidArgument
            }

            Write-Message -Level Output -Message "Connecting to SQL WMI on $($instance.ComputerName)."
            try {
                $sqlwmi = Invoke-ManagedComputerCommand -ComputerName $resolved.FQDN -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($($instance.InstanceName))"
            }
            catch {
                Stop-Function -Message "Failed to access $instance." -Target $instance -Continue -ErrorRecord $_
            }

            $regroot = ($sqlwmi.AdvancedProperties | Where-Object Name -eq REGROOT).Value
            $vsname = ($sqlwmi.AdvancedProperties | Where-Object Name -eq VSNAME).Value
            try {
                $instancename = $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(
            }
            catch {
                # Probably because the instance name has been aliased or does not exist or samthin
            }
            $serviceaccount = $sqlwmi.ServiceAccount

            if ([System.String]::IsNullOrEmpty($regroot)) {
                $regroot = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                $vsname = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }

                if (![System.String]::IsNullOrEmpty($regroot)) {
                    $regroot = ($regroot -Split 'Value\=')[1]
                    $vsname = ($vsname -Split 'Value\=')[1]
                }
                else {
                    Stop-Function -Message "Can't find instance $vsname on $instance." -Continue -Category ObjectNotFound -Target $instance
                }
            }

            if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $instance }

            Write-Message -Level Output -Message "Regroot: $regroot" -Target $instance
            Write-Message -Level Output -Message "ServiceAcct: $serviceaccount" -Target $instance
            Write-Message -Level Output -Message "InstanceName: $instancename" -Target $instance
            Write-Message -Level Output -Message "VSNAME: $vsname" -Target $instance

            $scriptblock = {
                $regpath = "Registry::HKEY_LOCAL_MACHINE\$($args[0])\MSSQLServer\SuperSocketNetLib"
                $cert = (Get-ItemProperty -Path $regpath -Name Certificate).Certificate
                $oldvalue = (Get-ItemProperty -Path $regpath -Name ForceEncryption).ForceEncryption
                Set-ItemProperty -Path $regpath -Name ForceEncryption -Value $false
                $forceencryption = (Get-ItemProperty -Path $regpath -Name ForceEncryption).ForceEncryption

                [pscustomobject]@{
                    ComputerName          = $env:COMPUTERNAME
                    InstanceName          = $args[2]
                    SqlInstance           = $args[1]
                    ForceEncryption       = ($forceencryption -eq $true)
                    CertificateThumbprint = $cert
                }
            }

            if ($PScmdlet.ShouldProcess("local", "Connecting to $instance to modify the ForceEncryption value in $regroot for $($instance.InstanceName)")) {
                try {
                    Invoke-Command2 -ComputerName $resolved.fqdn -Credential $Credential -ArgumentList $regroot, $vsname, $instancename -ScriptBlock $scriptblock -ErrorAction Stop
                    Write-Message -Level Critical -Message "Force encryption was successfully set on $($resolved.fqdn) for the $instancename instance. You must now restart the SQL Server for changes to take effect." -Target $instance
                }
                catch {
                    Stop-Function -Message "Failed to connect to $($resolved.fqdn) using PowerShell remoting!" -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}