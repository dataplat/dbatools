
function Remove-DbaNetworkCertificate {
    <#
    .SYNOPSIS
        Removes the SSL certificate configuration from SQL Server network encryption settings

    .DESCRIPTION
        Removes the certificate thumbprint from SQL Server's network encryption configuration by clearing the Certificate registry value in SuperSocketNetLib. This disables forced SSL encryption for client connections and returns the instance to unencrypted or optional encryption mode. Use this when decommissioning certificates, troubleshooting SSL connection issues, or when you need to reconfigure encryption settings from scratch.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost. If target is a cluster, you must also specify InstanceClusterName (see below)

    .PARAMETER Credential
        Windows credentials for accessing the target computer's registry and WMI services. This is used for computer-level authentication, not SQL Server authentication.
        Required when the current user lacks administrative privileges on the target server or when running against remote servers in different domains.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

        Returns one object per SQL Server instance where the network certificate configuration was removed.

        Default display properties:
        - ComputerName: The name of the computer where the certificate was removed
        - InstanceName: The SQL Server instance name (extracted from DisplayName)
        - SqlInstance: The full SQL Server instance identifier (VSNAME)
        - ServiceAccount: The service account used by the SQL Server instance
        - RemovedThumbprint: The certificate thumbprint that was removed (or $null if none was configured)

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaNetworkCertificate

    .EXAMPLE
        PS C:\> Remove-DbaNetworkCertificate

        Removes the Network Certificate for the default instance (MSSQLSERVER) on localhost

    .EXAMPLE
        PS C:\> Remove-DbaNetworkCertificate -SqlInstance sql1\SQL2008R2SP2

        Removes the Network Certificate for the SQL2008R2SP2 instance on sql1

    .EXAMPLE
        PS C:\> Remove-DbaNetworkCertificate -SqlInstance localhost\SQL2008R2SP2 -WhatIf

        Shows what would happen if the command were run

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low", DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        # Registry access


        foreach ($instance in $SqlInstance) {
            $stepCounter = 0
            Write-Message -Level VeryVerbose -Message "Processing $instance" -Target $instance
            $null = Test-ElevationRequirement -ComputerName $instance -Continue

            try {
                Write-Message -Level Verbose -Message "Resolving hostname."
                $resolved = $null
                $resolved = Resolve-DbaNetworkName -ComputerName $instance -Credential $Credential -EnableException
            } catch {
                $resolved = Resolve-DbaNetworkName -ComputerName $instance -Credential $Credential -Turbo
            }

            if ($null -eq $resolved) {
                Stop-Function -Message "Can't resolve $instance" -Target $instance -Continue -Category InvalidArgument
            }

            try {
                $sqlwmi = Invoke-ManagedComputerCommand -ComputerName $resolved.FQDN -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($($instance.InstanceName))"
            } catch {
                Stop-Function -Message "Failed to access $instance" -Target $instance -Continue -ErrorRecord $_
            }

            $regRoot = ($sqlwmi.AdvancedProperties | Where-Object Name -eq REGROOT).Value
            $vsname = ($sqlwmi.AdvancedProperties | Where-Object Name -eq VSNAME).Value
            $instanceName = $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(
            $serviceAccount = $sqlwmi.ServiceAccount

            if ([System.String]::IsNullOrEmpty($regRoot)) {
                $regRoot = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                $vsname = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }

                if (![System.String]::IsNullOrEmpty($regRoot)) {
                    $regRoot = ($regRoot -Split 'Value\=')[1]
                    $vsname = ($vsname -Split 'Value\=')[1]
                } else {
                    Stop-Function -Message "Can't find instance $vsname on $instance" -Continue -Category ObjectNotFound -Target $instance
                }
            }

            if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $instance }

            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Regroot: $regRoot" -Target $instance
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "ServiceAcct: $serviceAccount" -Target $instance
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "InstanceName: $instanceName" -Target $instance
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "VSNAME: $vsname" -Target $instance

            $scriptblock = {
                $regRoot = $args[0]
                $serviceAccount = $args[1]
                $instanceName = $args[2]
                $vsname = $args[3]

                $regPath = "Registry::HKEY_LOCAL_MACHINE\$($regRoot)\MSSQLServer\SuperSocketNetLib"
                $thumbprint = (Get-ItemProperty -Path $regPath -Name Certificate).Certificate
                Set-ItemProperty -Path $regPath -Name Certificate -Value $null

                [PSCustomObject]@{
                    ComputerName      = $env:COMPUTERNAME
                    InstanceName      = $instanceName
                    SqlInstance       = $vsname
                    ServiceAccount    = $serviceAccount
                    RemovedThumbprint = $thumbprint
                }
            }

            if ($PScmdlet.ShouldProcess("local", "Connecting to $ComputerName to remove the cert")) {
                try {
                    Invoke-Command2 -ComputerName $resolved.fqdn -Credential $Credential -ArgumentList $regRoot, $serviceAccount, $instanceName, $vsname -ScriptBlock $scriptblock -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failed to connect to $($resolved.fqdn) using PowerShell remoting." -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}