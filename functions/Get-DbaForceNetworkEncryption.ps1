function Get-DbaForceNetworkEncryption {
    <#
    .SYNOPSIS
        Gets Force Encryption settings for a SQL Server instance

    .DESCRIPTION
        Gets Force Encryption settings for a SQL Server instance. Note that this requires access to the Windows Server - not the SQL instance itself.

        This setting is found in Configuration Manager.

    .PARAMETER SqlInstance
       The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to the computer (not sql instance) using alternative Windows credentials

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaForceNetworkEncryption

    .EXAMPLE
        PS C:\> Get-DbaForceNetworkEncryption

        Gets Force Encryption properties on the default (MSSQLSERVER) instance on localhost - requires (and checks for) RunAs admin.

    .EXAMPLE
        PS C:\> Get-DbaForceNetworkEncryption -SqlInstance sql01\SQL2008R2SP2

        Gets Force Network Encryption for the SQL2008R2SP2 on sql01. Uses Windows Credentials to both login and view the registry.

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
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
                $sqlwmi = Invoke-ManagedComputerCommand -ComputerName $resolved.FullComputerName -ScriptBlock {
                    $wmi.Services
                } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($($instance.InstanceName))"
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
                $regRoot = $sqlwmi.AdvancedProperties | Where-Object {
                    $_ -match 'REGROOT'
                }
                $vsname = $sqlwmi.AdvancedProperties | Where-Object {
                    $_ -match 'VSNAME'
                }

                if (![System.String]::IsNullOrEmpty($regRoot)) {
                    $regRoot = ($regRoot -Split 'Value\=')[1]
                    $vsname = ($vsname -Split 'Value\=')[1]
                } else {
                    Stop-Function -Message "Can't find instance $vsname on $instance" -Continue -Category ObjectNotFound -Target $instance
                }
            }

            if ([System.String]::IsNullOrEmpty($vsname)) {
                $vsname = $instance
            }

            Write-Message -Level Verbose -Message "Regroot: $regRoot" -Target $instance
            Write-Message -Level Verbose -Message "ServiceAcct: $serviceAccount" -Target $instance
            Write-Message -Level Verbose -Message "InstanceName: $instanceName" -Target $instance
            Write-Message -Level Verbose -Message "VSNAME: $vsname" -Target $instance

            $scriptBlock = {
                $regPath = "Registry::HKEY_LOCAL_MACHINE\$($args[0])\MSSQLServer\SuperSocketNetLib"
                $cert = (Get-ItemProperty -Path $regPath -Name Certificate).Certificate
                $forceencryption = (Get-ItemProperty -Path $regPath -Name ForceEncryption).ForceEncryption

                # [pscustomobject] doesn't always work, unsure why. so return hashtable then turn it into  pscustomobject on client
                @{
                    ComputerName          = $env:COMPUTERNAME
                    InstanceName          = $args[2]
                    SqlInstance           = $args[1]
                    ForceEncryption       = ($forceencryption -eq $true)
                    CertificateThumbprint = $cert
                }
            }

            try {
                $results = Invoke-Command2 -ComputerName $resolved.FullComputerName -Credential $Credential -ArgumentList $regRoot, $vsname, $instanceName -ScriptBlock $scriptBlock -ErrorAction Stop -Raw
                foreach ($result in $results) {
                    [pscustomobject]$result
                }
            } catch {
                Stop-Function -Message "Failed to connect to $($resolved.FullComputerName) using PowerShell remoting" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}