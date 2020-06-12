
function Remove-DbaNetworkCertificate {
    <#
    .SYNOPSIS
        Removes the network certificate for SQL Server instance

    .DESCRIPTION
        Removes the network certificate for SQL Server instance. This setting is found in Configuration Manager.

    .PARAMETER SqlInstance
       The target SQL Server instance or instances. Defaults to localhost. If target is a cluster, you must also specify InstanceClusterName (see below)

    .PARAMETER Credential
        Allows you to login to the computer (not sql instance) using alternative credentials.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Certificate
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
                $cert = (Get-ItemProperty -Path $regPath -Name Certificate).Certificate
                Set-ItemProperty -Path $regPath -Name Certificate -Value $null

                [pscustomobject]@{
                    ComputerName      = $env:COMPUTERNAME
                    InstanceName      = $instanceName
                    SqlInstance       = $vsname
                    ServiceAccount    = $serviceAccount
                    RemovedThumbprint = $cert.Thumbprint
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