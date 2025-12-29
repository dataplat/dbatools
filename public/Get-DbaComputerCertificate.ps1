function Get-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Retrieves X.509 certificates from Windows certificate stores that can be used for SQL Server TLS encryption

    .DESCRIPTION
        Scans Windows certificate stores to find X.509 certificates suitable for enabling SQL Server network encryption. By default, returns only certificates with Server Authentication capability from the LocalMachine\My store, which are the certificates SQL Server can actually use for TLS connections. This saves you from manually browsing certificate stores and checking enhanced key usage extensions when configuring Force Encryption or setting up secure SQL Server connections.

    .PARAMETER ComputerName
        Specifies the target computer(s) to scan for certificates. Defaults to localhost.
        Use this when you need to check certificates on remote SQL Server machines or when configuring network encryption across multiple instances.
        For SQL Server clusters, specify each individual cluster node separately since certificates are stored per machine, not per cluster resource.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER Store
        Specifies which Windows certificate store location to search. Defaults to LocalMachine.
        Use LocalMachine for certificates that SQL Server service accounts can access, or CurrentUser for user-specific certificates.
        SQL Server typically requires certificates in LocalMachine store for network encryption to work properly.

    .PARAMETER Folder
        Specifies which certificate folder within the store to search. Defaults to My (Personal certificates).
        Use My for personal certificates with private keys, Root for trusted root certificates, or other folders based on certificate type.
        SQL Server network encryption typically uses certificates from the My folder since they contain the required private keys.

    .PARAMETER Path
        Specifies the file system path to a certificate file (.cer, .crt, .pfx) to load and analyze.
        Use this when you need to examine a certificate file before installing it to a certificate store.
        This bypasses the Store and Folder parameters since the certificate is loaded directly from the file system.

    .PARAMETER Type
        Filters certificates by their intended usage. Service returns only certificates with Server Authentication capability, All returns every certificate.
        Use Service (default) to find certificates that SQL Server can actually use for network encryption and TLS connections.
        Service certificates have the required Enhanced Key Usage extension (1.3.6.1.5.5.7.3.1) that enables them for server authentication scenarios.

    .PARAMETER Thumbprint
        Filters results to return only certificates with the specified thumbprint(s). Accepts multiple thumbprints.
        Use this when you need to verify specific certificates exist or check their properties before configuring SQL Server network encryption.
        The thumbprint is the unique SHA-1 hash identifier that SQL Server uses in its certificate configuration.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Security
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaComputerCertificate

    .OUTPUTS
        System.Security.Cryptography.X509Certificates.X509Certificate2

        Returns one X509Certificate2 object per certificate found in the specified store and folder.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer where the certificate is stored
        - Store: The certificate store location (CurrentUser or LocalMachine)
        - Folder: The certificate folder/container name (My, Root, AddressBook, etc.)
        - Name: The friendly name of the certificate (added via Add-Member)
        - DnsNameList: Collection of DNS names associated with the certificate
        - Thumbprint: The SHA-1 hash fingerprint uniquely identifying the certificate
        - NotBefore: DateTime when the certificate becomes valid
        - NotAfter: DateTime when the certificate expires
        - Subject: The distinguished name of the subject (entity the certificate is issued to)
        - Issuer: The distinguished name of the certificate issuer (CA that signed it)
        - Algorithm: The signature algorithm used by the certificate (added via Add-Member)

        Additional properties available from the X509Certificate2 object:
        - PublicKey: The public key cryptographic information
        - PrivateKey: The private key (when available)
        - Version: The X.509 certificate version
        - SerialNumber: The serial number assigned by the issuer
        - SignatureAlgorithm: Algorithm details for the certificate signature
        - Extensions: Collection of certificate extensions
        - SignatureAlgorithmOid: Object identifier for the signature algorithm
        - IssuerName: X500DistinguishedName of the issuer
        - SubjectName: X500DistinguishedName of the subject
        - Verify: Method to verify the certificate

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate

        Gets computer certificates on localhost that are candidates for using with SQL Server's network encryption

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate -ComputerName sql2016

        Gets computer certificates on sql2016 that are candidates for using with SQL Server's network encryption

    .EXAMPLE
        PS C:\> Get-DbaComputerCertificate -ComputerName sql2016 -Thumbprint 8123472E32AB412ED4288888B83811DB8F504DED, 04BFF8B3679BB01A986E097868D8D494D70A46D6

        Gets computer certificates on sql2016 that match thumbprints 8123472E32AB412ED4288888B83811DB8F504DED or 04BFF8B3679BB01A986E097868D8D494D70A46D6
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string[]]$Store = "LocalMachine",
        [string[]]$Folder = "My",
        [ValidateSet("All", "Service")]
        [string]$Type = "Service",
        [string]$Path,
        [string[]]$Thumbprint,
        [switch]$EnableException
    )

    begin {
        #region Scriptblock for remoting
        $scriptBlock = {
            param (
                $Thumbprint,
                $Store,
                $Folder,
                $Path
            )

            if ($Path) {
                $bytes = [System.IO.File]::ReadAllBytes($path)
                $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                $Certificate.Import($bytes, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
                return $Certificate
            }

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

                foreach ($c in $certs) {
                    Add-Member -Force -InputObject $c -NotePropertyName Algorithm -NotePropertyValue $c.SignatureAlgorithm.FriendlyName
                    Add-Member -Force -InputObject $c -NotePropertyName ComputerName -NotePropertyValue $env:ComputerName
                    # had to add Name because remotely, "FriendlyName" refused to work. no idea why.
                    Add-Member -Force -InputObject $c -NotePropertyName Name -NotePropertyValue $c.FriendlyName.ToString()
                    Add-Member -Force -InputObject $c -NotePropertyName Store -NotePropertyValue $Store
                    Add-Member -Force -InputObject $c -NotePropertyName Folder -NotePropertyValue $Folder -Passthru
                }
            }

            if ($Thumbprint) {
                try {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose "Searching Cert:\$Store\$Folder"
                    Get-CoreCertificate -Store $Store -Folder $Folder -Thumbprint $Thumbprint
                } catch {
                    # don't care - there's a weird issue with remoting where an exception gets thrown for no apparent reason
                    # here to avoid an empty catch
                    $null = 1
                }
            } else {
                try {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose "Searching Cert:\$Store\$Folder"
                    if ($Type -eq "Service") {
                        Get-CoreCertificate -Store $Store -Folder $Folder | Where-Object EnhancedKeyUsageList -match '1\.3\.6\.1\.5\.5\.7\.3\.1'
                    } else {
                        Get-CoreCertificate -Store $Store -Folder $Folder
                    }
                } catch {
                    # still don't care
                    # here to avoid an empty catch
                    $null = 1
                }
            }
        }
        #endregion Scriptblock for remoting
    }

    process {
        foreach ($computer in $computername) {
            if ($Store -eq "All") {
                try {
                    $Store = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock { Get-ChildItem Cert: | Select-Object -ExpandProperty Location } -Raw
                } catch {
                    Stop-Function -Message "Issue connecting to computer" -ErrorRecord $_ -Target $computer -Continue
                }
            }
            if ($Folder -eq "All") {
                try {
                    $Folder = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock { Get-ChildItem Cert: | Select-Object -ExpandProperty StoreNames | Select-Object -ExpandProperty Keys } -Raw
                } catch {
                    Stop-Function -Message "Issue connecting to computer" -ErrorRecord $_ -Target $computer -Continue
                }
            }
            foreach ($currentStore in $Store) {
                foreach ($currentFolder in $Folder) {
                    try {
                        Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $thumbprint, $currentStore, $currentFolder, $Path -ErrorAction Stop | Select-DefaultView -Property ComputerName, Store, Folder, Name, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer, Algorithm
                    } catch {
                        Stop-Function -Message "Issue connecting to computer" -ErrorRecord $_ -Target $computer -Continue
                    }
                }
            }
        }
    }
}