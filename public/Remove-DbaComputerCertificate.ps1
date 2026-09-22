function Remove-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Removes certificates from Windows certificate stores on local or remote computers

    .DESCRIPTION
        Removes certificates from Windows certificate stores on local or remote computers using PowerShell remoting. This is essential for managing SSL/TLS certificates used by SQL Server instances for encrypted connections and authentication. DBAs commonly use this to clean up expired certificates, remove compromised certificates during security incidents, or manage certificate lifecycle during SQL Server migrations and decommissions. The function targets specific certificates by thumbprint and can work across multiple certificate stores and folders.

        Removing a certificate from a store leaves its private key on disk, as the certificate console does. With -DeleteKey the private key is deleted as well, unless another certificate in the LocalMachine store or in the CurrentUser store of the account running the command still uses it.

    .PARAMETER ComputerName
        Specifies the target computer(s) where certificates will be removed. Defaults to localhost.
        Use this when managing SSL certificates across multiple SQL Server instances or cleaning up certificates on remote servers during migrations.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials

    .PARAMETER Thumbprint
        Specifies the unique thumbprint(s) of the certificate(s) to remove. This is the SHA-1 hash that uniquely identifies each certificate.
        Use Get-DbaComputerCertificate to find thumbprints of certificates you want to remove, commonly needed when cleaning up expired SSL certificates or removing compromised certificates.
        An archived certificate, which the certificate console and Get-DbaComputerCertificate hide, is removed as well when its thumbprint is given.

    .PARAMETER Store
        Specifies the certificate store location where certificates will be removed. Defaults to LocalMachine.
        Use LocalMachine for system-wide certificates (typical for SQL Server SSL certificates) or CurrentUser for user-specific certificates.

    .PARAMETER Folder
        Specifies the certificate store folder (subfolder) where certificates will be removed. Defaults to 'My' (Personal certificates).
        Common folders include 'My' for SSL certificates used by SQL Server, 'Root' for trusted root certificates, or 'TrustedPeople' for trusted person certificates.

    .PARAMETER DeleteKey
        Deletes the private key of the certificate together with the certificate, like the DeleteKey switch of the Cert: drive in Windows PowerShell.
        Works for keys in a legacy Cryptographic Service Provider (what New-DbaComputerCertificate creates) and in a Key Storage Provider (CNG).
        Before the key is deleted, every folder of the LocalMachine store and of the CurrentUser store of the account running the command is checked for another certificate that still uses the key, archived certificates included, for example a copy of the certificate in another folder (WebHosting and custom folders included) or in the other store, or a renewed certificate that reused the key. If one exists the key is kept and the output says which one.
        Another certificate is recognized by the key reference stored with it: the provider, the key container and whether the key is a machine key. That reference is read from the certificate, so no private key of another certificate is opened; a smart card certificate in the store of the user would otherwise prompt for the card. A certificate that holds the same key in a container of its own, for example the same PFX file imported once for the machine and once for the user, does not keep the key, because deleting one container leaves the other one intact.
        The key is also kept when a folder of either store cannot be read, because then it is unknown whether a certificate in that folder uses the key; the output names the folder.
        A legacy Cryptographic Service Provider container can hold a key exchange key and a signature key and can only be deleted as a whole, so it is kept when a certificate still uses the other key; the output names that certificate.
        The personal stores of other accounts on the computer cannot be checked, because they are only available to those accounts. A key that only a certificate in one of them still uses is deleted.

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
        - PrivateKey: What happened to the private key. "Kept" without -DeleteKey, "Deleted" with -DeleteKey, "Kept, shared with <thumbprint> in <store>" when another certificate still uses the key, "Kept, key container shared with <thumbprint> in <store>" when a certificate still uses the other key of a legacy container, "Not deleted: <reason>" when the deletion failed, "None" when the certificate has no private key, $null when the certificate was not found

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
                    [string]$Folder,
                    [ValidateSet("ReadOnly", "ReadWrite")]
                    [string]$Flag = "ReadOnly"
                )

                # The folder is opened by name, so folders the StoreName enumeration does not know, like WebHosting, work too.
                # OpenExistingOnly keeps a mistyped folder name from being created as a new empty store. IncludeArchived shows
                # archived certificates as well, which a store hides by default; the thumbprint names the certificate exactly.
                $storename = [System.Security.Cryptography.X509Certificates.StoreLocation]::$Store
                $flags = [System.Security.Cryptography.X509Certificates.OpenFlags]$Flag -bor [System.Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly -bor [System.Security.Cryptography.X509Certificates.OpenFlags]::IncludeArchived
                $certstore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $Folder, $storename
                $certstore.Open($flags)

                $certstore
            }

            function Get-CoreCertificate {
                [CmdletBinding()]
                param (
                    [ValidateSet("CurrentUser", "LocalMachine")]
                    [string]$Store,
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

            function Get-CoreRsaModulus {
                # Returns the modulus of an RSA public key as a string, or $null for another key type. The modulus identifies
                # the key pair, and it comes from the certificate without opening the private key.
                [CmdletBinding()]
                param (
                    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
                )
                $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Certificate)
                if ($null -ne $rsa) {
                    [Convert]::ToBase64String($rsa.ExportParameters($false).Modulus)
                }
            }

            function Get-CoreKeyProviderInfo {
                # Returns the key reference stored with the certificate: the provider, the key container, whether the key
                # is in the machine key set and the key specification. It is a property of the certificate, so reading it
                # does not open the key and cannot prompt, unlike opening the key of a smart card certificate would.
                # Returns $null when the certificate carries no key reference.
                [CmdletBinding()]
                param (
                    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
                )
                if (-not ("Dbatools.Certificate.KeyProviderInfo" -as [type])) {
                    $keyProviderInfoSource = @"
using System;
using System.Runtime.InteropServices;

namespace Dbatools.Certificate {
    public class KeyProviderInfo {
        public string ContainerName;
        public string ProviderName;
        public uint ProviderType;
        public bool MachineKeySet;
        public uint KeySpec;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct CRYPT_KEY_PROV_INFO {
            public string pwszContainerName;
            public string pwszProvName;
            public uint dwProvType;
            public uint dwFlags;
            public uint cProvParam;
            public IntPtr rgProvParam;
            public uint dwKeySpec;
        }

        private const uint CERT_KEY_PROV_INFO_PROP_ID = 2;
        private const uint CRYPT_MACHINE_KEYSET = 0x20;

        [DllImport("crypt32.dll", SetLastError = true)]
        private static extern bool CertGetCertificateContextProperty(IntPtr pCertContext, uint dwPropId, IntPtr pvData, ref uint pcbData);

        public static KeyProviderInfo Read(IntPtr certContext) {
            uint size = 0;
            if (!CertGetCertificateContextProperty(certContext, CERT_KEY_PROV_INFO_PROP_ID, IntPtr.Zero, ref size)) {
                return null;
            }
            IntPtr buffer = Marshal.AllocHGlobal((int)size);
            try {
                if (!CertGetCertificateContextProperty(certContext, CERT_KEY_PROV_INFO_PROP_ID, buffer, ref size)) {
                    return null;
                }
                CRYPT_KEY_PROV_INFO info = (CRYPT_KEY_PROV_INFO)Marshal.PtrToStructure(buffer, typeof(CRYPT_KEY_PROV_INFO));
                KeyProviderInfo result = new KeyProviderInfo();
                result.ContainerName = info.pwszContainerName;
                result.ProviderName = info.pwszProvName;
                result.ProviderType = info.dwProvType;
                result.MachineKeySet = (info.dwFlags & CRYPT_MACHINE_KEYSET) != 0;
                result.KeySpec = info.dwKeySpec;
                return result;
            } finally {
                Marshal.FreeHGlobal(buffer);
            }
        }
    }
}
"@
                    Add-Type -TypeDefinition $keyProviderInfoSource
                }
                [Dbatools.Certificate.KeyProviderInfo]::Read($Certificate.Handle)
            }

            function Remove-CoreCertificateKey {
                # Deletes the key container. A legacy CSP key is deleted through its own provider, because deleting it
                # through the CNG bridge leaves the key file behind. Returns $null on success, otherwise the reason of
                # the failure.
                [CmdletBinding()]
                param (
                    [System.Security.Cryptography.CngKey]$Key,
                    [string]$Modulus
                )
                $legacyProviderPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography\Defaults\Provider\$($Key.Provider.Provider)"
                if (Test-Path -Path $legacyProviderPath) {
                    $providerType = (Get-ItemProperty -Path $legacyProviderPath -Name Type).Type
                    # A legacy container can hold two keys, KeyNumber 1 is AT_KEYEXCHANGE and 2 is AT_SIGNATURE, and it is
                    # deleted as a whole through either of them. The key of this certificate is the one with the modulus of
                    # the certificate; that a certificate still uses the other key was ruled out by the scan.
                    $cspKey = $null
                    $lastError = $null
                    foreach ($keyNumber in 1, 2) {
                        try {
                            $cspParameters = New-Object System.Security.Cryptography.CspParameters -ArgumentList $providerType, $Key.Provider.Provider, $Key.KeyName
                            $cspParameters.KeyNumber = $keyNumber
                            $cspParameters.Flags = [System.Security.Cryptography.CspProviderFlags]::UseExistingKey
                            if ($Key.IsMachineKey) {
                                $cspParameters.Flags = $cspParameters.Flags -bor [System.Security.Cryptography.CspProviderFlags]::UseMachineKeyStore
                            }
                            $containerKey = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList $cspParameters
                            if ([Convert]::ToBase64String($containerKey.ExportParameters($false).Modulus) -eq $Modulus) {
                                $cspKey = $containerKey
                            }
                        } catch {
                            $lastError = $_.Exception.Message
                        }
                    }
                    if ($null -eq $cspKey) {
                        if ($lastError) {
                            return $lastError
                        }
                        return "the key container does not hold the key of the certificate"
                    }
                    try {
                        $cspKey.PersistKeyInCsp = $false
                        $cspKey.Clear()
                        return $null
                    } catch {
                        return $_.Exception.Message
                    }
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
                    }
                }

                $certstore = Get-CoreCertStore -Store $Store -Folder $Folder -Flag ReadWrite
                $certstore.Remove($cert)
                $status = "Removed"

                if ($null -ne $key) {
                    # Another certificate may use the same key, for example a copy of this certificate in another folder
                    # or a renewed certificate that reused the key. Then the key stays. A copy keeps its key reference
                    # across store locations as well: a machine certificate copied into CurrentUser\My still points at
                    # the machine key. So both locations are scanned whatever -Store says. The personal stores of other
                    # accounts are out of reach, they live in those accounts' registry hives.
                    # The scan runs after the certificate is removed, because some CurrentUser folders (Root, CA,
                    # TrustedPeople, ...) also show the certificates of the LocalMachine folder of the same name. Once
                    # the certificate is gone from its folder that mirror image is gone too, whereas a real copy stays.
                    # The folders come from the Cert: drive, because the StoreName enumeration does not know the WebHosting
                    # folder of IIS or custom folders, and a copy in one of those has to keep the key as well.
                    $unlistedLocations = @()
                    # A folder is listed from the registry, but opening it or reading its certificates can still fail,
                    # for example when the caller has no read access to that folder. Then the scan is incomplete and
                    # the key has to stay, because that folder may hold a certificate that uses it.
                    $unreadableFolders = @()
                    $localMachineMatches = @()
                    # No other certificate's private key is opened during the scan: a smart card certificate in the user's
                    # store, for example, would prompt for the card. Another certificate uses this key when the key reference
                    # stored with it names the same container: the same key set (machine or user), the same container name
                    # and the same provider family. A machine certificate may name a legacy container by its unique name
                    # while the key reports the friendly name, so both names of this key count. Every legacy Microsoft RSA
                    # provider opens the same containers, so the provider name only matters for a Key Storage Provider.
                    # The same key in a container of its own, for example the same PFX file imported once for the machine
                    # and once for the user, is not touched by deleting this container and does not keep it. A certificate
                    # without a readable key reference keeps the key when it has the same public key, because then it is
                    # unknown which container it uses.
                    $publicKey = [Convert]::ToBase64String($cert.GetPublicKey())
                    $modulus = Get-CoreRsaModulus -Certificate $cert
                    $containerNames = @($key.KeyName, $key.UniqueName)
                    $legacyProvider = Test-Path -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography\Defaults\Provider\$($key.Provider.Provider)"
                    $containerSharedWith = @()
                    $sharedWith = foreach ($scanLocation in "LocalMachine", "CurrentUser") {
                        $storeLocation = [System.Security.Cryptography.X509Certificates.StoreLocation]::$scanLocation
                        try {
                            $storeNames = (Get-ChildItem -Path "Cert:\$scanLocation" -ErrorAction Stop).Name
                        } catch {
                            $storeNames = $null
                        }
                        if (-not $storeNames) {
                            $unlistedLocations += "Cert:\$scanLocation"
                            continue
                        }
                        foreach ($storeName in $storeNames) {
                            $otherStore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $storeName, $storeLocation
                            try {
                                # Archived certificates are hidden unless asked for, and one of them may use the key as well.
                                $otherStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]"ReadOnly, OpenExistingOnly, IncludeArchived")
                                foreach ($otherCert in $otherStore.Certificates) {
                                    if (-not $otherCert.HasPrivateKey) {
                                        continue
                                    }
                                    # A LocalMachine certificate mirrored into the CurrentUser folder of the same name is not reported twice.
                                    if ($scanLocation -eq "CurrentUser" -and "$storeName\$($otherCert.Thumbprint)" -in $localMachineMatches) {
                                        continue
                                    }
                                    $samePublicKey = [Convert]::ToBase64String($otherCert.GetPublicKey()) -eq $publicKey
                                    $otherKeyInfo = Get-CoreKeyProviderInfo -Certificate $otherCert
                                    if ($null -eq $otherKeyInfo) {
                                        $sameContainer = $samePublicKey
                                    } elseif ($otherKeyInfo.MachineKeySet -ne $key.IsMachineKey -or $otherKeyInfo.ContainerName -notin $containerNames) {
                                        $sameContainer = $false
                                    } elseif ($legacyProvider) {
                                        $sameContainer = $otherKeyInfo.ProviderType -ne 0
                                    } else {
                                        $sameContainer = $otherKeyInfo.ProviderType -eq 0 -and $otherKeyInfo.ProviderName -eq $key.Provider.Provider
                                    }
                                    if (-not $sameContainer) {
                                        continue
                                    }
                                    if ($scanLocation -eq "LocalMachine") {
                                        $localMachineMatches += "$storeName\$($otherCert.Thumbprint)"
                                    }
                                    if ($samePublicKey) {
                                        "$($otherCert.Thumbprint) in Cert:\$scanLocation\$storeName"
                                    } else {
                                        # A legacy container with two keys, and the other certificate uses the other key.
                                        $containerSharedWith += "$($otherCert.Thumbprint) in Cert:\$scanLocation\$storeName"
                                    }
                                }
                            } catch {
                                $unreadableFolders += "Cert:\$scanLocation\$storeName"
                            } finally {
                                $otherStore.Close()
                            }
                        }
                    }

                    if ($unlistedLocations) {
                        $privateKey = "Not deleted: the folders of $($unlistedLocations -join ", ") could not be listed, so it is unknown whether another certificate uses the key"
                    } elseif ($sharedWith) {
                        $privateKey = "Kept, shared with $($sharedWith -join ", ")"
                    } elseif ($containerSharedWith) {
                        $privateKey = "Kept, key container shared with $($containerSharedWith -join ", ")"
                    } elseif ($unreadableFolders) {
                        $privateKey = "Not deleted: $($unreadableFolders -join ", ") could not be read, so it is unknown whether another certificate uses the key"
                    } else {
                        $keyFile = $null
                        if ($key.IsMachineKey) {
                            foreach ($keyPath in ($env:ProgramData + "\Microsoft\Crypto\RSA\MachineKeys\"), ($env:ProgramData + "\Microsoft\Crypto\Keys\")) {
                                if (Test-Path -Path ($keyPath + $key.UniqueName) -PathType Leaf) {
                                    $keyFile = $keyPath + $key.UniqueName
                                }
                            }
                        }
                        $reason = Remove-CoreCertificateKey -Key $key -Modulus $modulus
                        if ($reason) {
                            $privateKey = "Not deleted: $reason"
                        } elseif ($keyFile -and (Test-Path -Path $keyFile -PathType Leaf)) {
                            $privateKey = "Not deleted: the key file $keyFile is still there"
                        } else {
                            $privateKey = "Deleted"
                        }
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