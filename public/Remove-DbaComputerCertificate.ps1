function Remove-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Removes certificates from Windows certificate stores on local or remote computers

    .DESCRIPTION
        Removes certificates from Windows certificate stores on local or remote computers using PowerShell remoting. This is essential for managing SSL/TLS certificates used by SQL Server instances for encrypted connections and authentication. DBAs commonly use this to clean up expired certificates, remove compromised certificates during security incidents, or manage certificate lifecycle during SQL Server migrations and decommissions. The function targets specific certificates by thumbprint and can work across multiple certificate stores and folders.

        Removing a certificate from a store leaves its private key on disk, as the certificate console does. With -DeleteKey the private key is deleted as well, unless another certificate in the same store location still uses it.

    .PARAMETER ComputerName
        Specifies the target computer(s) where certificates will be removed. Defaults to localhost.
        Use this when managing SSL certificates across multiple SQL Server instances or cleaning up certificates on remote servers during migrations.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials

    .PARAMETER Thumbprint
        Specifies the unique thumbprint(s) of the certificate(s) to remove. This is the SHA-1 hash that uniquely identifies each certificate.
        Use Get-DbaComputerCertificate to find thumbprints of certificates you want to remove, commonly needed when cleaning up expired SSL certificates or removing compromised certificates.

    .PARAMETER Store
        Specifies the certificate store location where certificates will be removed. Defaults to LocalMachine.
        Use LocalMachine for system-wide certificates (typical for SQL Server SSL certificates) or CurrentUser for user-specific certificates.

    .PARAMETER Folder
        Specifies the certificate store folder (subfolder) where certificates will be removed. Defaults to 'My' (Personal certificates).
        Common folders include 'My' for SSL certificates used by SQL Server, 'Root' for trusted root certificates, or 'TrustedPeople' for trusted person certificates.

    .PARAMETER DeleteKey
        Deletes the private key of the certificate together with the certificate, like the DeleteKey switch of the Cert: drive in Windows PowerShell.
        Works for keys in a legacy Cryptographic Service Provider (what New-DbaComputerCertificate creates) and in a Key Storage Provider (CNG).
        The key is kept when another certificate in the same store location still uses it, for example a copy of the certificate in another folder or a renewed certificate that reused the key; the output says which one.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .OUTPUTS
        PSCustomObject

        Returns one object per certificate removal attempt. Each object contains the following properties:
        - ComputerName: The computer name where the certificate removal was attempted
        - Store: The certificate store location (LocalMachine or CurrentUser)
        - Folder: The certificate store folder/subfolder where the certificate was located (My, Root, TrustedPeople, etc.)
        - Thumbprint: The SHA-1 hash thumbprint of the certificate that was targeted for removal
        - Status: The status of the removal operation. Shows "Removed" on success, or "Certificate not found in Cert:\$Store\$Folder" if the certificate was not found
        - PrivateKey: What happened to the private key. "Kept" without -DeleteKey, "Deleted" with -DeleteKey, "Kept, shared with <thumbprint> in <store>" when another certificate still uses the key, "Not deleted: <reason>" when the deletion failed, "None" when the certificate has no private key, $null when the certificate was not found

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaComputerCertificate

    .EXAMPLE
        PS C:\> Remove-DbaComputerCertificate -ComputerName Server1 -Thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94

        Removes certificate with thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94 in the LocalMachine store on Server1

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate | Where-Object Thumbprint -eq E0A071E387396723C45E92D42B2D497C6A182340 | Remove-DbaComputerCertificate

        Removes certificate using the pipeline

    .EXAMPLE
        PS C:\> Remove-DbaComputerCertificate -ComputerName Server1 -Thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94 -Store User -Folder My

        Removes certificate with thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94 in the User\My (Personal) store on Server1

    .EXAMPLE
        PS C:\> Remove-DbaComputerCertificate -ComputerName Server1 -Thumbprint C2BBE81A94FEE7A26FFF86C2DFDAF6BFD28C6C94 -DeleteKey

        Removes the certificate from the LocalMachine\My store on Server1 and deletes its private key, unless another certificate on Server1 still uses that key

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [parameter(ValueFromPipelineByPropertyName, Mandatory)]
        [string[]]$Thumbprint,
        [string]$Store = "LocalMachine",
        [string]$Folder = "My",
        [switch]$DeleteKey,
        [switch]$EnableException
    )

    begin {
        #region Scriptblock for remoting
        $scriptBlock = {
            param (
                $Thumbprint,
                $Store,
                $Folder,
                $DeleteKey
            )
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose "Searching Cert:\$Store\$Folder for thumbprint: $thumbprint"
            function Get-CoreCertStore {
                [CmdletBinding()]
                param (
                    [ValidateSet("CurrentUser", "LocalMachine")]
                    [string]$Store,
                    [ValidateSet("AddressBook", "AuthRoot, CertificateAuthority", "Disallowed", "My", "Root", "TrustedPeople", "TrustedPublisher")]
                    [string]$Folder,
                    [ValidateSet("ReadOnly", "ReadWrite")]
                    [string]$Flag = "ReadOnly"
                )

                $storename = [System.Security.Cryptography.X509Certificates.StoreLocation]::$Store
                $foldername = [System.Security.Cryptography.X509Certificates.StoreName]::$Folder
                $flags = [System.Security.Cryptography.X509Certificates.OpenFlags]::$Flag
                $certstore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $foldername, $storename
                $certstore.Open($flags)

                $certstore
            }

            function Get-CoreCertificate {
                [CmdletBinding()]
                param (
                    [ValidateSet("CurrentUser", "LocalMachine")]
                    [string]$Store,
                    [ValidateSet("AddressBook", "AuthRoot, CertificateAuthority", "Disallowed", "My", "Root", "TrustedPeople", "TrustedPublisher")]
                    [string]$Folder,
                    [ValidateSet("ReadOnly", "ReadWrite")]
                    [string]$Flag = "ReadOnly",
                    [string[]]$Thumbprint,
                    [System.Security.Cryptography.X509Certificates.X509Store[]]$InputObject
                )

                if (-not $InputObject) {
                    $InputObject += Get-CoreCertStore -Store $Store -Folder $Folder -Flag $Flag
                }

                $certs = ($InputObject).Certificates

                if ($Thumbprint) {
                    $certs = $certs | Where-Object Thumbprint -in $Thumbprint
                }
                $certs
            }

            function Get-CoreCertificateKey {
                # Returns the CNG key of the private key, or $null when the certificate has none or it cannot be opened.
                # A legacy CSP key comes back through the CNG bridge, so this works for both provider generations and
                # in both PowerShell editions, where $cert.PrivateKey does not.
                [CmdletBinding()]
                param (
                    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
                )
                $key = $null
                try {
                    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
                    if ($null -ne $rsa -and $rsa.GetType().FullName -eq "System.Security.Cryptography.RSACng") {
                        $key = $rsa.Key
                    } elseif ($null -eq $rsa) {
                        $ecdsa = [System.Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPrivateKey($Certificate)
                        if ($null -ne $ecdsa -and $ecdsa.GetType().FullName -eq "System.Security.Cryptography.ECDsaCng") {
                            $key = $ecdsa.Key
                        }
                    }
                } catch {
                    $key = $null
                }
                $key
            }

            function Remove-CoreCertificateKey {
                # Deletes the key container. A legacy CSP key is deleted through its own provider, because deleting it
                # through the CNG bridge leaves the key file behind. Returns $null on success, otherwise the reason.
                [CmdletBinding()]
                param (
                    [System.Security.Cryptography.CngKey]$Key
                )
                $legacyProviderPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography\Defaults\Provider\$($Key.Provider.Provider)"
                if (Test-Path -Path $legacyProviderPath) {
                    $providerType = (Get-ItemProperty -Path $legacyProviderPath -Name Type).Type
                    $lastError = $null
                    # KeyNumber 1 is AT_KEYEXCHANGE, 2 is AT_SIGNATURE; the container holds one of them.
                    foreach ($keyNumber in 1, 2) {
                        try {
                            $cspParameters = New-Object System.Security.Cryptography.CspParameters -ArgumentList $providerType, $Key.Provider.Provider, $Key.KeyName
                            $cspParameters.KeyNumber = $keyNumber
                            $cspParameters.Flags = [System.Security.Cryptography.CspProviderFlags]::UseExistingKey
                            if ($Key.IsMachineKey) {
                                $cspParameters.Flags = $cspParameters.Flags -bor [System.Security.Cryptography.CspProviderFlags]::UseMachineKeyStore
                            }
                            $cspKey = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList $cspParameters
                            $cspKey.PersistKeyInCsp = $false
                            $cspKey.Clear()
                            return $null
                        } catch {
                            $lastError = $_.Exception.Message
                        }
                    }
                    return $lastError
                }
                try {
                    $Key.Delete()
                    return $null
                } catch {
                    return $_.Exception.Message
                }
            }

            if ($Thumbprint) {
                try {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose "Searching Cert:\$Store\$Folder"
                    $cert = Get-CoreCertificate -Store $Store -Folder $Folder -Thumbprint $Thumbprint
                } catch {
                    # don't care - there's a weird issue with remoting where an exception gets thrown for no apparent reason
                    # here to avoid an empty catch
                    $null = 1
                }
            }

            $privateKey = $null
            if ($cert) {
                $key = $null
                if (-not $cert.HasPrivateKey) {
                    $privateKey = "None"
                } elseif (-not $DeleteKey) {
                    $privateKey = "Kept"
                } else {
                    # Everything about the key is read while the certificate is still in the store.
                    $key = Get-CoreCertificateKey -Certificate $cert
                    if ($null -eq $key) {
                        $privateKey = "Not deleted: the private key could not be opened"
                    } else {
                        # Another certificate in the same store location may use the same key, for example a copy of this
                        # certificate in another folder or a renewed certificate that reused the key. Then the key stays.
                        $storeLocation = [System.Security.Cryptography.X509Certificates.StoreLocation]::$Store
                        $sharedWith = foreach ($storeName in [System.Enum]::GetValues([System.Security.Cryptography.X509Certificates.StoreName])) {
                            $otherStore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $storeName, $storeLocation
                            try {
                                $otherStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
                                foreach ($otherCert in $otherStore.Certificates) {
                                    if (-not $otherCert.HasPrivateKey) {
                                        continue
                                    }
                                    if ($otherCert.Thumbprint -eq $cert.Thumbprint -and "$storeName" -eq $Folder) {
                                        continue
                                    }
                                    $otherKey = Get-CoreCertificateKey -Certificate $otherCert
                                    if ($null -ne $otherKey -and $otherKey.UniqueName -eq $key.UniqueName) {
                                        "$($otherCert.Thumbprint) in Cert:\$Store\$storeName"
                                    }
                                }
                            } catch {
                                # A store that cannot be opened holds no certificate that could share the key.
                                $null = 1
                            } finally {
                                $otherStore.Close()
                            }
                        }
                        if ($sharedWith) {
                            $privateKey = "Kept, shared with $($sharedWith -join ", ")"
                            $key = $null
                        }
                    }
                }

                $certstore = Get-CoreCertStore -Store $Store -Folder $Folder -Flag ReadWrite
                $certstore.Remove($cert)
                $status = "Removed"

                if ($null -ne $key) {
                    $keyFile = $null
                    if ($key.IsMachineKey) {
                        foreach ($keyPath in ($env:ProgramData + "\Microsoft\Crypto\RSA\MachineKeys\"), ($env:ProgramData + "\Microsoft\Crypto\Keys\")) {
                            if (Test-Path -Path ($keyPath + $key.UniqueName) -PathType Leaf) {
                                $keyFile = $keyPath + $key.UniqueName
                            }
                        }
                    }
                    $reason = Remove-CoreCertificateKey -Key $key
                    if ($reason) {
                        $privateKey = "Not deleted: $reason"
                    } elseif ($keyFile -and (Test-Path -Path $keyFile -PathType Leaf)) {
                        $privateKey = "Not deleted: the key file $keyFile is still there"
                    } else {
                        $privateKey = "Deleted"
                    }
                }
            } else {
                $status = "Certificate not found in Cert:\$Store\$Folder"
            }

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                Store        = $Store
                Folder       = $Folder
                Thumbprint   = $thumbprint
                Status       = $status
                PrivateKey   = $privateKey
            }
        }
        #endregion Scriptblock for remoting
    }

    process {
        foreach ($computer in $computername) {
            foreach ($thumb in $Thumbprint) {
                if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to remove cert from Cert:\$Store\$Folder")) {
                    try {
                        $splatInvoke = @{
                            ComputerName = $computer
                            Credential   = $Credential
                            ArgumentList = $thumb, $Store, $Folder, [bool]$DeleteKey
                            ScriptBlock  = $scriptBlock
                            ErrorAction  = "Stop"
                        }
                        Invoke-Command2 @splatInvoke
                    } catch {
                        Stop-Function -Message $_ -ErrorRecord $_ -Target $computer -Continue
                    }
                }
            }
        }
    }
}