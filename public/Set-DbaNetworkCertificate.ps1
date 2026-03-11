function Set-DbaNetworkCertificate {
    <#
    .SYNOPSIS
        Sets the network certificate for SQL Server instance

    .DESCRIPTION
        Sets the network certificate for SQL Server instance. This setting is found in Configuration Manager.

        This command also grants read permissions for the service account on the certificate's private key.

        Before setting the certificate, the command uses Test-DbaNetworkCertificate to verify that
        the certificate is suitable for SQL Server network encryption. Use -SkipCertificateValidation
        to bypass this check if needed.

        References:
        https://www.itprotoday.com/sql-server/7-steps-ssl-encryption
        https://azurebi.jppp.org/2016/01/23/using-lets-encrypt-certificates-for-secure-sql-server-connections/
        https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/
        https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/certificate-requirements

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER Credential
        Allows you to login to the computer (not sql instance) using alternative credentials.

    .PARAMETER Certificate
        Specifies the X509Certificate2 object to configure as the network certificate for SQL Server.
        Use this when piping certificate objects from other dbatools commands like New-DbaComputerCertificate.
        The certificate must exist in the LocalMachine certificate store and have a private key for SQL Server to use it for SSL connections.

    .PARAMETER Thumbprint
        Specifies the thumbprint (SHA-1 hash) of the certificate to configure as the network certificate.
        Use this when you know the specific certificate thumbprint from certificates already installed in LocalMachine\My.
        Must be a 40-character hexadecimal string (no spaces). The certificate must have a private key and the SQL Server
        service account will be granted read permissions to it.

    .PARAMETER RestartService
        Forces an automatic restart of the SQL Server service after setting the network certificate.
        Certificate changes require a service restart to take effect - without this switch you'll need to manually restart SQL Server.
        Use this when you want the SSL configuration to be immediately active, but be aware it will cause a brief service interruption.

    .PARAMETER SkipCertificateValidation
        Skips the certificate suitability validation performed by Test-DbaNetworkCertificate.
        By default, the command verifies the certificate meets all SQL Server requirements before setting it.
        Use this switch only if you need to set a certificate that does not pass all validation checks.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .NOTES
        Tags: Certificate, Security
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaNetworkCertificate

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance processed, containing the following properties:

        - ComputerName: The name of the computer where the SQL Server instance is hosted
        - InstanceName: The SQL Server instance name (e.g., MSSQLSERVER, SQL2008R2SP2)
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ServiceAccount: The service account running the SQL Server instance
        - CertificateThumbprint: The SHA-1 thumbprint of the newly configured certificate in lowercase
        - Notes: Summary of actions performed, including whether an old certificate was replaced and which service account was granted read permissions

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate | Set-DbaNetworkCertificate -SqlInstance localhost\SQL2008R2SP2

        Creates and imports a new certificate signed by an Active Directory CA on localhost then sets the network certificate for the SQL2008R2SP2 to that newly created certificate.

    .EXAMPLE
        PS C:\> Set-DbaNetworkCertificate -SqlInstance sql1\SQL2008R2SP2 -Thumbprint 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2

        Sets the network certificate for the SQL2008R2SP2 instance to the certificate with the thumbprint of 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2 in LocalMachine\My on sql1

    .EXAMPLE
        PS C:\> Set-DbaNetworkCertificate -SqlInstance sql1 -Thumbprint 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2 -SkipCertificateValidation

        Sets the network certificate on sql1, skipping the certificate suitability validation. Use when you need to set a certificate that does not fully pass the Test-DbaNetworkCertificate checks.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias("ComputerName")]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [Parameter(ValueFromPipeline)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidatePattern('^[0-9A-Fa-f]{40}$')]
        [string]$Thumbprint,
        [switch]$RestartService,
        [switch]$SkipCertificateValidation,
        [switch]$EnableException
    )

    process {
        # Registry access

        if (Test-FunctionInterrupt) { return }

        if (-not $Certificate -and -not $Thumbprint) {
            Stop-Function -Message "You must specify a certificate or thumbprint"
            return
        }

        if (Test-Bound -ParameterName Certificate) {
            Write-Message -Level SomewhatVerbose -Message "Getting thumbprint"
            $Thumbprint = $Certificate.Thumbprint
        }

        foreach ($instance in $SqlInstance) {
            $stepCounter = 0
            Write-Message -Level VeryVerbose -Message "Processing $instance" -Target $instance
            $null = Test-ElevationRequirement -ComputerName $instance -Continue


            $computerName = $instance.ComputerName
            $instanceName = $instance.instancename

            try {
                # removed: Resolve-DbaNetworkName command as it is used in the Invoke-ManagedComputerCommand anyway
                $sqlwmi = Invoke-ManagedComputerCommand -ComputerName $computerName -ScriptBlock { $wmi.Services } -Credential $Credential -ErrorAction Stop | Where-Object DisplayName -eq "SQL Server ($instanceName)"
            } catch {
                Stop-Function -Message "Failed to access $instance" -Target $instance -Continue -ErrorRecord $_
                continue
            }

            if (-not $sqlwmi) {
                Stop-Function -Message "Cannot find $instanceName on $computerName" -Continue -Category ObjectNotFound -Target $instance
                continue
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
                    continue
                }
            }

            if ([System.String]::IsNullOrEmpty($vsname)) { $vsname = $instance }

            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Regroot: $regRoot" -Target $instance
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "ServiceAcct: $serviceAccount" -Target $instance
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "InstanceName: $instanceName" -Target $instance
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "VSNAME: $vsname" -Target $instance

            if (-not $SkipCertificateValidation) {
                Write-Message -Level Verbose -Message "Validating certificate $Thumbprint for $instance using Test-DbaNetworkCertificate"
                try {
                    $splatTest = @{
                        SqlInstance     = $instance
                        Credential      = $Credential
                        Thumbprint      = $Thumbprint
                        EnableException = $true
                    }
                    $certTest = Test-DbaNetworkCertificate @splatTest
                } catch {
                    Stop-Function -Message "Failed to validate certificate $Thumbprint for $instance" -Target $instance -ErrorRecord $_ -Continue
                    continue
                }

                if (-not $certTest.IsSuitable) {
                    $failedChecks = @()
                    if (-not $certTest.CertificateFound) { $failedChecks += "CertificateNotFound" }
                    if ($certTest.CertificateFound -and -not $certTest.KeyUsagesValid) { $failedChecks += "KeyUsagesInvalid" }
                    if ($certTest.CertificateFound -and -not $certTest.DnsNamesValid) { $failedChecks += "DnsNamesInvalid" }
                    if ($certTest.CertificateFound -and -not $certTest.PrivateKeyValid) { $failedChecks += "PrivateKeyInvalid" }
                    if ($certTest.CertificateFound -and -not $certTest.PublicKeyValid) { $failedChecks += "PublicKeyInvalid" }
                    if ($certTest.CertificateFound -and -not $certTest.SignatureAlgorithmValid) { $failedChecks += "SignatureAlgorithmInvalid" }
                    if ($certTest.CertificateFound -and -not $certTest.EnhancedKeyUsageValid) { $failedChecks += "EnhancedKeyUsageInvalid" }
                    if ($certTest.CertificateFound -and -not $certTest.ValidityPeriodOk) { $failedChecks += "ValidityPeriodExpiredOrInsufficient" }
                    Stop-Function -Message "Certificate $Thumbprint is not suitable for SQL Server network encryption on $instance. Failed checks: $($failedChecks -join ', '). Use -SkipCertificateValidation to override." -Target $instance -Continue
                    continue
                }

                Write-Message -Level Verbose -Message "Certificate $Thumbprint passed all validation checks for $instance"
            }

            $scriptBlock = {
                $regRoot = $args[0]
                $serviceAccount = $args[1]
                $instanceName = $args[2]
                $vsname = $args[3]
                $Thumbprint = $args[4]

                $regPath = "Registry::HKEY_LOCAL_MACHINE\$regRoot\MSSQLServer\SuperSocketNetLib"

                $oldThumbprint = (Get-ItemProperty -Path $regPath -Name Certificate -ErrorAction SilentlyContinue).Certificate

                $cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction Stop | Where-Object { $_.Thumbprint -eq $Thumbprint }

                if ($null -eq $cert) {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Warning "Certificate does not exist in LocalMachine\My on $env:COMPUTERNAME"
                    return
                }

                if (-not $cert.HasPrivateKey) {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Warning "Certificate $Thumbprint does not have a private key on $env:COMPUTERNAME"
                    return
                }

                #Grant permissions to the Service SID
                $sqlSSID = "NT SERVICE\MSSQLSERVER"
                if ($instanceName -ne "MSSQLSERVER") {
                    $sqlSSID = "NT SERVICE\MSSQL$" + $instanceName
                }

                $permission = $serviceAccount, "Read", "Allow"
                $accessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission
                $permission = $sqlSSID, "Read", "Allow"
                $accessRuleSSID = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission

                if ($null -ne $cert.PrivateKey) {
                    $keyPath = $env:ProgramData + "\Microsoft\Crypto\RSA\MachineKeys\"
                    if ($PSVersionTable.PSVersion.Major -ge 6) {
                        $keyName = $cert.PrivateKey.Key.UniqueName
                    } else {
                        $keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
                    }
                    $keyFullPath = $keyPath + $keyName
                } else {
                    $keyPath = $env:ProgramData + '\Microsoft\Crypto\Keys\'
                    $algorithm = $cert.GetKeyAlgorithm()

                    if ($algorithm.StartsWith("1.2.840.10045")) {
                        $ecdsaKey = [System.Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPrivateKey($cert)
                        $keyName = $ecdsaKey.Key.UniqueName
                    } elseif ($algorithm.StartsWith("1.2.840.113549")) {
                        $rsaKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
                        $keyName = $rsaKey.Key.UniqueName
                    } elseif ($algorithm.StartsWith("1.3.14.3.2.12")) {
                        $rsaKey = [System.Security.Cryptography.X509Certificates.DSACertificateExtensions]::GetDSAPrivateKey($cert)
                        $keyName = $rsaKey.Key.UniqueName
                    } else {
                        Write-Warning "Unknown certificate key algorithm OID ""$algorithm""."
                    }

                    $keyFullPath = $keyPath + $keyName
                }

                if (-not (Test-Path $keyFullPath -Type Leaf)) {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Warning "Read-only permissions could not be granted to certificate, unable to determine private key path."
                    return
                }

                try {
                    $acl = Get-Acl -Path $keyFullPath
                    $null = $acl.AddAccessRule($accessRule)
                    $null = $acl.AddAccessRule($accessRuleSSID)
                    Set-Acl -Path $keyFullPath -AclObject $acl
                } catch {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Warning "Failed to set read permissions on certificate private key: $_"
                    return
                }

                Set-ItemProperty -Path $regPath -Name Certificate -Value $Thumbprint.ToString().ToLowerInvariant() # to make it compat with SQL config

                if (![System.String]::IsNullOrEmpty($oldThumbprint)) {
                    $notes = "Granted $serviceAccount read access to certificate private key. Replaced thumbprint: $oldThumbprint."
                } else {
                    $notes = "Granted $serviceAccount read access to certificate private key"
                }

                $newThumbprint = (Get-ItemProperty -Path $regPath -Name Certificate).Certificate

                [PSCustomObject]@{
                    ComputerName          = $env:COMPUTERNAME
                    InstanceName          = $instanceName
                    SqlInstance           = $vsname
                    ServiceAccount        = $serviceAccount
                    CertificateThumbprint = $newThumbprint
                    Notes                 = $notes
                }
            }

            if ($PScmdlet.ShouldProcess("local", "Connecting to $instanceName to import new cert")) {
                try {
                    Invoke-Command2 -Raw -ComputerName $computerName -Credential $Credential -ArgumentList $regRoot, $serviceAccount, $instanceName, $vsname, $Thumbprint -ScriptBlock $scriptBlock -ErrorAction Stop
                    if ($RestartService) {
                        $null = Restart-DbaService -SqlInstance $instance -Force
                    } else {
                        Write-Message -Level Warning -Message "New certificate will not take effect until SQL Server services are restarted for $instance"
                    }
                } catch {
                    Stop-Function -Message "Failed to connect to $computerName using PowerShell remoting." -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }
    }
}
