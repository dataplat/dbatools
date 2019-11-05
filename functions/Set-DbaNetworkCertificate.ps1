function Set-DbaNetworkCertificate {
    <#
    .SYNOPSIS
        Sets the network certificate for SQL Server instance

    .DESCRIPTION
        Sets the network certificate for SQL Server instance. This setting is found in Configuration Manager.

        This command also grants read permissions for the service account on the certificate's private key.

        References:
        http://sqlmag.com/sql-server/7-steps-ssl-encryption
        https://azurebi.jppp.org/2016/01/23/using-lets-encrypt-certificates-for-secure-sql-server-connections/
        https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/

    .PARAMETER SqlInstance
       The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to the computer (not sql instance) using alternative credentials.

    .PARAMETER Certificate
        The target certificate object

    .PARAMETER Thumbprint
        The thumbprint of the target certificate

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
        https://dbatools.io/Set-DbaNetworkCertificate

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate | Set-DbaNetworkCertificate -SqlInstance localhost\SQL2008R2SP2

        Creates and imports a new certificate signed by an Active Directory CA on localhost then sets the network certificate for the SQL2008R2SP2 to that newly created certificate.

    .EXAMPLE
        PS C:\> Set-DbaNetworkCertificate -SqlInstance sql1\SQL2008R2SP2 -Thumbprint 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2

        Sets the network certificate for the SQL2008R2SP2 instance to the certificate with the thumbprint of 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2 in LocalMachine\My on sql1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low", DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias("ComputerName")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [parameter(Mandatory, ParameterSetName = "Certificate", ValueFromPipeline)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [parameter(Mandatory, ParameterSetName = "Thumbprint", ValueFromPipelineByPropertyName)]
        [string]$Thumbprint,
        [switch]$EnableException
    )

    process {
        # Registry access

        if (Test-FunctionInterrupt) { return }

        if (-not $Certificate -and -not $Thumbprint) {
            Stop-Function -Message "You must specify a certificate or thumbprint"
            return
        }

        if (-not $Thumbprint) {
            Write-Message -Level SomewhatVerbose -Message "Getting thumbprint"
            $Thumbprint = $Certificate.Thumbprint
        }

        foreach ($instance in $sqlinstance) {
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

            $computername = $instance.ComputerName
            $instancename = $instance.instancename

            try {
                $sqlwmi = Invoke-ManagedComputerCommand -ComputerName $resolved.FQDN -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($instancename)"
            } catch {
                Stop-Function -Message "Failed to access $instance" -Target $instance -Continue -ErrorRecord $_
            }

            if (-not $sqlwmi) {
                Stop-Function -Message "Cannot find $instancename on $computerName" -Continue -Category ObjectNotFound -Target $instance
            }

            $regroot = ($sqlwmi.AdvancedProperties | Where-Object Name -eq REGROOT).Value
            $vsname = ($sqlwmi.AdvancedProperties | Where-Object Name -eq VSNAME).Value
            $instancename = $sqlwmi.DisplayName.Replace('SQL Server (', '').Replace(')', '') # Don't clown, I don't know regex :(
            $serviceaccount = $sqlwmi.ServiceAccount

            if ([System.String]::IsNullOrEmpty($regroot)) {
                $regroot = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                $vsname = $sqlwmi.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }

                if (![System.String]::IsNullOrEmpty($regroot)) {
                    $regroot = ($regroot -Split 'Value\=')[1]
                    $vsname = ($vsname -Split 'Value\=')[1]
                } else {
                    Stop-Function -Message "Can't find instance $vsname on $instance" -Continue -Category ObjectNotFound -Target $instance
                }
            }

            if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $instance }

            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Regroot: $regroot" -Target $instance
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "ServiceAcct: $serviceaccount" -Target $instance
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "InstanceName: $instancename" -Target $instance
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "VSNAME: $vsname" -Target $instance

            $scriptblock = {
                $regroot = $args[0]
                $serviceaccount = $args[1]
                $instancename = $args[2]
                $vsname = $args[3]
                $Thumbprint = $args[4]

                $regpath = "Registry::HKEY_LOCAL_MACHINE\$regroot\MSSQLServer\SuperSocketNetLib"

                $oldthumbprint = (Get-ItemProperty -Path $regpath -Name Certificate).Certificate

                $cert = Get-ChildItem Cert:\LocalMachine -Recurse -ErrorAction Stop | Where-Object { $_.Thumbprint -eq $Thumbprint }

                if ($null -eq $cert) {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Warning "Certificate does not exist on $env:COMPUTERNAME"
                    return
                }

                $permission = $serviceaccount, "Read", "Allow"
                $accessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission

                if ($null -ne $cert.PrivateKey) {
                    $keyPath = $env:ProgramData + "\Microsoft\Crypto\RSA\MachineKeys\"
                    $keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
                    $keyFullPath = $keyPath + $keyName
                } else {
                    $keyPath = $env:ProgramData + '\Microsoft\Crypto\Keys\'
                    $rsaKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
                    $keyName = $rsaKey.Key.UniqueName
                    $KeyFullPath = $keyPath + $keyName
                }

                if (-not (Test-Path $KeyFullPath -Type Leaf)) {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Warning "Read-only permissions could not be granted to certificate, unable to determine private key path."
                    return
                }

                $acl = Get-Acl -Path $keyFullPath
                $null = $acl.AddAccessRule($accessRule)
                Set-Acl -Path $keyFullPath -AclObject $acl

                if ($acl) {
                    Set-ItemProperty -Path $regpath -Name Certificate -Value $Thumbprint.ToString().ToLowerInvariant() # to make it compat with SQL config
                } else {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Warning "Read-only permissions could not be granted to certificate"
                    return
                }

                if (![System.String]::IsNullOrEmpty($oldthumbprint)) {
                    $notes = "Granted $serviceaccount read access to certificate private key. Replaced thumbprint: $oldthumbprint."
                } else {
                    $notes = "Granted $serviceaccount read access to certificate private key"
                }

                $newthumbprint = (Get-ItemProperty -Path $regpath -Name Certificate).Certificate

                [pscustomobject]@{
                    ComputerName          = $env:COMPUTERNAME
                    InstanceName          = $instancename
                    SqlInstance           = $vsname
                    ServiceAccount        = $serviceaccount
                    CertificateThumbprint = $newthumbprint
                    Notes                 = $notes
                }
            }

            if ($PScmdlet.ShouldProcess("local", "Connecting to $instanceName to import new cert")) {
                try {
                    Invoke-Command2 -Raw -ComputerName $resolved.fqdn -Credential $Credential -ArgumentList $regroot, $serviceaccount, $instancename, $vsname, $Thumbprint -ScriptBlock $scriptblock -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failed to connect to $($resolved.fqdn) using PowerShell remoting." -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}