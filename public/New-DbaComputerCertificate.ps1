function New-DbaComputerCertificate {
    <#
    .SYNOPSIS
        Creates a new computer certificate useful for Forcing Encryption

    .DESCRIPTION
        Creates a new computer certificate - self-signed or signed by an Active Directory CA, using the Web Server certificate.

        By default, a key with a length of 2048 bits and a friendly name of "SQL Server" is generated. The private key
        is created by the legacy Microsoft RSA SChannel Cryptographic Provider unless -Provider asks for a Key Storage Provider.

        This command was originally intended to help automate the process so that SSL certificates can be available for enforcing encryption on connections.

        It makes a lot of assumptions - namely, that your account is allowed to auto-enroll and that you have permission to do everything it needs to do ;)

        References:
        https://www.itprotoday.com/sql-server/7-steps-ssl-encryption
        https://azurebi.jppp.org/2016/01/23/using-lets-encrypt-certificates-for-secure-sql-server-connections/
        https://blogs.msdn.microsoft.com/sqlserverfaq/2016/09/26/creating-and-registering-ssl-certificates/

        The certificate is generated using AD's webserver SSL template on the client machine and pushed to the remote machine.

        The command leaves nothing behind on the computer it runs on: the copy of a self-signed certificate that certreq puts into the intermediate CA store is removed right away, a request the CA did not answer is removed from the REQUEST store together with its key, and a certificate created for another computer is removed from the local store together with its key once it has been exported.

    .PARAMETER ComputerName
        Specifies the target computer or computers where the certificate will be created and installed. Defaults to localhost.
        For SQL Server clusters, specify each cluster node here and use ClusterInstanceName for the cluster's virtual name.
        The certificate is created locally and then copied to remote machines via WinRM if needed.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER CaServer
        Specifies the Certificate Authority server that will sign the certificate request.
        When omitted, the function automatically discovers the CA server from Active Directory.
        Required for domain-signed certificates when automatic discovery fails.

    .PARAMETER CaName
        Specifies the Certificate Authority name on the CA server.
        When omitted, the function automatically discovers the CA name from Active Directory.
        Must match the exact CA name as registered in the domain's PKI infrastructure.

    .PARAMETER ClusterInstanceName
        Specifies the virtual cluster name when creating certificates for SQL Server failover clusters.
        The certificate subject and SAN will use this cluster name instead of individual node names.
        Use ComputerName to specify each physical cluster node where the certificate will be installed.

    .PARAMETER SecurePassword
        Specifies the password used to protect the private key during certificate export and import operations.
        Required when installing certificates on remote machines to secure the private key during transport.
        The same password is used for both export from the local machine and import on remote machines.

    .PARAMETER FriendlyName
        Specifies the friendly name displayed in the certificate store to help identify the certificate.
        Defaults to "SQL Server" making it easy to locate certificates intended for SQL Server encryption.
        Choose descriptive names like "SQL Prod Cluster" or "SQL Dev Server" for better organization.

    .PARAMETER CertificateTemplate
        Specifies the Active Directory Certificate Template used for certificate generation.
        Defaults to "WebServer" which provides the necessary server authentication capabilities for SQL Server encryption.
        The template must exist in your domain's PKI and allow auto-enrollment for your account.

    .PARAMETER KeyLength
        Specifies the RSA key size in bits for the certificate's private key.
        Defaults to 2048 bits which meets current industry security standards for production environments.
        4096 bits can be used for high-security environments, though it may slightly impact performance during SSL handshakes.

    .PARAMETER Provider
        Specifies the cryptographic provider that generates and holds the private key.
        Defaults to "Microsoft RSA SChannel Cryptographic Provider", a legacy Cryptographic Service Provider (CSP) that creates the key with KeySpec AT_KEYEXCHANGE, which is what the Microsoft certificate requirements for SQL Server name.
        Use "Microsoft Software Key Storage Provider" for a Cryptography Next Generation (CNG) key. SQL Server 2019 and later load such a key as well, and Set-DbaNetworkCertificate and Test-DbaNetworkCertificate handle both key types.
        The key is generated on the machine that runs the command and travels with the PFX to a remote computer, so the provider is the same on the target.

    .PARAMETER Store
        Specifies the certificate store location where the certificate will be installed.
        Defaults to "LocalMachine" which makes certificates available to services like SQL Server.
        Use "CurrentUser" only for user-specific certificates that don't need service access.

    .PARAMETER Folder
        Specifies the certificate store folder where the certificate will be placed.
        Defaults to "My" (Personal certificates) which is where SQL Server looks for server certificates.
        Use "TrustedPeople" or other folders only for specific certificate trust scenarios.

    .PARAMETER Flag
        Specifies how the certificate's private key should be handled during import operations.
        Defaults to "Exportable, PersistKeySet" allowing the key to be backed up and persisted on disk.
        Use "NonExportable" for high-security environments where private keys should never leave the machine.
        When copying certificates to remote computers, the temporary source certificate remains exportable so the destination import can honor the requested flags.
        "UserProtected" requires interactive confirmation and only works on localhost installations.

    .PARAMETER Dns
        Specifies additional DNS names to include in the certificate's Subject Alternative Name (SAN) extension.
        By default, includes the computer name and FQDN, or cluster name and cluster FQDN for clusters.
        Add extra DNS names that clients will use to connect, such as aliases or load balancer names.

    .PARAMETER SelfSigned
        Creates a self-signed certificate instead of requesting one from a Certificate Authority.
        Useful for development environments or when no domain CA is available.
        Self-signed certificates will generate trust warnings unless manually added to client trust stores.

    .PARAMETER DocumentEncryptionCert
        Creates a certificate suitable for use as a Column Master Key for Always Encrypted.
        When specified, the certificate uses KeyEncipherment key usage and includes the
        Document Encryption (1.3.6.1.4.1.311.10.3.11) and IKE Intermediate (1.3.6.1.5.5.8.2.2)
        Extended Key Usage OIDs required by Always Encrypted, instead of the default Server
        Authentication OID (1.3.6.1.5.5.7.3.1).
        For CA-signed certificates, specify -CertificateTemplate with a template configured
        for Always Encrypted column master keys. The default WebServer template is intended
        for TLS server certificates and is not suitable for this switch.

    .PARAMETER HashAlgorithm
        Specifies the cryptographic hash algorithm used for certificate signing.
        Defaults to "Sha256" which meets current industry security standards for production environments.
        SHA-384 and SHA-512 provide even stronger security for high-security environments.

    .PARAMETER MonthsValid
        Specifies how many months the self-signed certificate remains valid from the creation date.
        Defaults to 12 months; use longer periods like 60 months (5 years) to reduce certificate renewal frequency.
        Only applies to self-signed certificates; CA-signed certificates use the CA's validity period.

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
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaComputerCertificate

    .OUTPUTS
        System.Security.Cryptography.X509Certificates.X509Certificate2

        Returns one or more X.509 certificate objects for the computers where certificates were successfully created and installed.

        For local host (-ComputerName localhost or not specified): Returns the certificate object created or imported on the local machine after certificate generation/signing completes.

        For remote hosts: Returns the certificate object after successful import on the remote computer via WinRM. When creating certificates for SQL Server failover clusters (-ClusterInstanceName specified), a single certificate is created and imported on each cluster node specified in -ComputerName.

        Default display properties (via Select-DefaultView):
        - FriendlyName: The friendly name assigned to the certificate (defaults to "SQL Server")
        - DnsNameList: Collection of DNS names in the certificate's Subject Alternative Name (SAN) extension
        - Thumbprint: The SHA-1 hash fingerprint of the certificate, used for certificate identification
        - NotBefore: DateTime when the certificate becomes valid
        - NotAfter: DateTime when the certificate expires
        - Subject: The certificate subject Distinguished Name (DN) containing the CN (Common Name)
        - Issuer: The issuer Distinguished Name (DN) for the certificate (either self-signed or CA name)

        Additional properties available via Select-Object *:
        - SerialNumber: The certificate's serial number
        - Version: The X.509 version number (typically 3)
        - SignatureAlgorithm: The signing algorithm used (e.g., sha256RSA, sha1RSA)
        - PublicKey: The certificate's public key information
        - PrivateKey: The private key associated with this certificate (if present and accessible)
        - Extensions: Collection of X.509 extensions (e.g., Subject Alternative Name, Enhanced Key Usage)

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate

        Creates a computer certificate signed by the local domain CA for the local machine with the keylength of 2048 and SHA-256 hashing.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -ComputerName Server1

        Creates a computer certificate signed by the local domain CA _on the local machine_ for server1 with the keylength of 2048 and SHA-256 hashing.

        The certificate is then copied to the new machine over WinRM and imported.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -ComputerName sqla, sqlb -ClusterInstanceName sqlcluster -KeyLength 4096

        Creates a computer certificate for sqlcluster, signed by the local domain CA, with the keylength of 4096.

        The certificate is then copied to sqla _and_ sqlb over WinRM and imported.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -ComputerName Server1 -WhatIf

        Shows what would happen if the command were run

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -SelfSigned

        Creates a self-signed certificate

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -SelfSigned -HashAlgorithm Sha256 -MonthsValid 60

        Creates a self-signed certificate using the SHA256 hashing algorithm that does not expire for 5 years

    .EXAMPLE
        PS C:\> New-DbaComputerCertificate -SelfSigned -DocumentEncryptionCert

        Creates a self-signed certificate suitable for use as a Column Master Key for Always Encrypted.
        The certificate includes the Document Encryption and IKE Intermediate Extended Key Usage OIDs
        required by SQL Server Always Encrypted.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string]$CaServer,
        [string]$CaName,
        [string]$ClusterInstanceName,
        [Alias("Password")]
        [securestring]$SecurePassword,
        [string]$FriendlyName = "SQL Server",
        [string]$CertificateTemplate = "WebServer",
        [int]$KeyLength = 2048,
        [ValidateSet("Microsoft RSA SChannel Cryptographic Provider", "Microsoft Software Key Storage Provider")]
        [string]$Provider = "Microsoft RSA SChannel Cryptographic Provider",
        [string]$Store = "LocalMachine",
        [string]$Folder = "My",
        [ValidateSet("EphemeralKeySet", "Exportable", "PersistKeySet", "UserProtected", "NonExportable")]
        [string[]]$Flag = @("Exportable", "PersistKeySet"),
        [string[]]$Dns,
        [switch]$SelfSigned,
        [switch]$DocumentEncryptionCert,
        [switch]$EnableException,
        [ValidateSet("Sha256", "sha384", "sha512")]
        [string]$HashAlgorithm = "Sha256",
        [int]$MonthsValid = 12
    )
    begin {
        if ("NonExportable" -in $Flag) {
            $flags = ($Flag | Where-Object { $PSItem -ne "Exportable" -and $PSItem -ne "NonExportable" } ) -join ","

            # It needs at least one flag
            if (-not $flags) {
                if ($Store -eq "LocalMachine") {
                    $flags = "MachineKeySet"
                } else {
                    $flags = "UserKeySet"
                }
            }
        } else {
            $flags = $Flag -join ","
        }

        if ($DocumentEncryptionCert -and -not $SelfSigned -and -not $PSBoundParameters.ContainsKey("CertificateTemplate")) {
            Stop-Function -Message "DocumentEncryptionCert requires -SelfSigned or an explicit -CertificateTemplate configured for Always Encrypted column master keys. The default WebServer template is intended for TLS server certificates."
            return
        }

        $englishCodes = 9, 1033, 2057, 3081, 4105, 5129, 6153, 7177, 8201, 9225
        if ($englishCodes -notcontains (Get-DbaCmObject -ClassName Win32_OperatingSystem).OSLanguage) {
            Stop-Function -Message "Currently, this command is only supported in English OS locales. OS Locale detected: $([System.Globalization.CultureInfo]::GetCultureInfo([int](Get-DbaCmObject Win32_OperatingSystem).OSLanguage).DisplayName)`nWe apologize for the inconvenience and look into providing universal language support in future releases."
            return
        }

        if (-not (Test-ElevationRequirement -ComputerName $env:COMPUTERNAME)) {
            return
        }

        function GetHexLength {
            [cmdletbinding()]
            param(
                [int]$strLen
            )
            $hex = [String]::Format("{0:X2}", $strLen)

            if (($hex.length % 2) -gt 0) { $hex = "0$hex" }

            if ($strLen -gt 127) { [String]::Format("{0:X2}", 128 + ($hex.Length / 2)) + $hex }
            else { $hex }
        }

        function Get-SanExt {
            [cmdletbinding()]
            param(
                [string[]]$hostName
            )
            # thanks to Lincoln of
            # https://social.technet.microsoft.com/Forums/windows/en-US/f568edfa-7f93-46a4-aab9-a06151592dd9/converting-ascii-to-asn1-der

            $temp = ''
            foreach ($fqdn in $hostName) {
                # convert each character of fqdn to hex
                $hexString = ($fqdn.ToCharArray() | ForEach-Object { [String]::Format("{0:X2}", [int]$_) }) -join ''

                # length of hex fqdn, in hex
                $hexLength = GetHexLength ($hexString.Length / 2)

                # concatenate special code 82, hex length, hex string
                $temp += "82${hexLength}${hexString}"
            }
            # calculate total length of concatenated string, in hex
            $totalHexLength = GetHexLength ($temp.Length / 2)
            # concatenate special code 30, hex length, hex string
            $temp = "30${totalHexLength}${temp}"
            # convert to binary
            $bytes = $(
                for ($i = 0; $i -lt $temp.Length; $i += 2) {
                    [byte]"0x$($temp.SubString($i, 2))"
                }
            )
            # convert to base 64
            $base64 = [Convert]::ToBase64String($bytes)
            # output in proper format
            for ($i = 0; $i -lt $base64.Length; $i += 64) {
                $line = $base64.SubString($i, [Math]::Min(64, $base64.Length - $i))
                if ($i -eq 0) { "2.5.29.17=$line" }
                else { "_continue_=$line" }
            }
        }

        if ((-not $CaServer -or !$CaName) -and !$SelfSigned) {
            try {
                Write-Message -Level Verbose -Message "No CaServer or CaName specified. Performing lookup."
                # hat tip Vadims Podans
                $domain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
                $domain = "DC=" + $domain -replace '\.', ", DC="
                $pks = [ADSI]"LDAP://CN=Enrollment Services, CN=Public Key Services, CN=Services, CN=Configuration, $domain"
                $cas = $pks.psBase.Children

                $allCas = @()
                foreach ($ca in $cas) {
                    $allCas += [PSCustomObject]@{
                        CA       = $ca | ForEach-Object { $_.Name }
                        Computer = $ca | ForEach-Object { $_.DNSHostName }
                    }
                }
            } catch {
                Stop-Function -Message "Cannot access Active Directory or find the Certificate Authority" -ErrorRecord $_
                return
            }

            if (-not $CaServer) {
                $CaServer = ($allCas | Select-Object -First 1).Computer
                Write-Message -Level Verbose -Message "Root Server: $CaServer"
            }

            if (-not $CaName) {
                $CaName = ($allCas | Select-Object -First 1).CA
                Write-Message -Level Verbose -Message "Root CA name: $CaName"
            }
        }

        $tempDir = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $certTemplate = "CertificateTemplate:$CertificateTemplate"
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # uses dos command locally


        foreach ($computer in $ComputerName) {
            $stepCounter = 0

            if (-not $secondaryNode) {

                if ($ClusterInstanceName) {
                    if ($ClusterInstanceName -notmatch "\.") {
                        $fqdn = "$ClusterInstanceName.$env:USERDNSDOMAIN"
                    } else {
                        $fqdn = $ClusterInstanceName
                    }
                } else {
                    $resolved = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -WarningAction SilentlyContinue

                    if (-not $resolved) {
                        $fqdn = "$ComputerName.$env:USERDNSDOMAIN"
                        Write-Message -Level Warning -Message "Server name cannot be resolved. Guessing it's $fqdn"
                    } else {
                        $fqdn = $resolved.fqdn
                    }
                }

                $certDir = "$tempDir\$fqdn"
                $certCfg = "$certDir\request.inf"
                $certCsr = "$certDir\$fqdn.csr"
                $certCrt = "$certDir\$fqdn.crt"
                $certPfx = "$certDir\$fqdn.pfx"
                $tempPfx = "$certDir\temp-$fqdn.pfx"

                if (Test-Path($certDir)) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Deleting files from $certDir"
                    $null = Remove-Item "$certDir\*.*"
                } else {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Creating $certDir"
                    $null = New-Item -Path $certDir -ItemType Directory -Force
                }

                # Make sure output is compat with clusters
                $shortName = $fqdn.Split(".")[0]

                if (-not $dns) {
                    $dns = $shortName, $fqdn
                }

                $san = Get-SanExt $dns
                # Write config file
                Set-Content $certCfg "[Version]"
                Add-Content $certCfg 'Signature="$Windows NT$"'
                Add-Content $certCfg "[NewRequest]"
                Add-Content $certCfg "Subject = ""CN=$fqdn"""
                if ($Provider -eq "Microsoft RSA SChannel Cryptographic Provider") {
                    # A legacy CSP key. KeySpec 1 is AT_KEYEXCHANGE, the KeySpec the Microsoft certificate requirements for SQL Server name.
                    Add-Content $certCfg "KeySpec = 1"
                }
                Add-Content $certCfg "KeyLength = $KeyLength"
                # Keep the source cert exportable whenever it must be copied to another host.
                if ("NonExportable" -in $Flag -and -not $ClusterInstanceName -and $computer.IsLocalHost) {
                    Add-Content $certCfg "Exportable = FALSE"
                } else {
                    Add-Content $certCfg "Exportable = TRUE"
                }
                Add-Content $certCfg "MachineKeySet = TRUE"
                Add-Content $certCfg "FriendlyName=""$FriendlyName"""
                Add-Content $certCfg "SMIME = False"
                Add-Content $certCfg "PrivateKeyArchive = FALSE"
                Add-Content $certCfg "UserProtected = FALSE"
                Add-Content $certCfg "UseExistingKeySet = FALSE"
                Add-Content $certCfg "ProviderName = ""$Provider"""
                if ($Provider -eq "Microsoft RSA SChannel Cryptographic Provider") {
                    # ProviderType 12 is PROV_RSA_SCHANNEL.
                    Add-Content $certCfg "ProviderType = 12"
                } else {
                    # A Key Storage Provider has neither a provider type nor a KeySpec, it takes the key algorithm instead.
                    Add-Content $certCfg "KeyAlgorithm = RSA"
                }
                if ($SelfSigned) {
                    Add-Content $certCfg "RequestType = Cert"
                    Add-Content $certCfg "NotBefore = $((Get-Date).ToShortDateString())"
                    Add-Content $certCfg "NotAfter = $((Get-Date).AddMonths($MonthsValid).ToShortDateString())"
                } else {
                    Add-Content $certCfg "RequestType = PKCS10"
                }
                Add-Content $certCfg "HashAlgorithm = $HashAlgorithm"
                if ($DocumentEncryptionCert) {
                    Add-Content $certCfg "KeyUsage = 0x20"
                    Add-Content $certCfg "[EnhancedKeyUsageExtension]"
                    Add-Content $certCfg "OID=1.3.6.1.5.5.8.2.2"
                    Add-Content $certCfg "OID=1.3.6.1.4.1.311.10.3.11"
                } else {
                    Add-Content $certCfg "KeyUsage = 0xa0"
                    Add-Content $certCfg "[EnhancedKeyUsageExtension]"
                    Add-Content $certCfg "OID=1.3.6.1.5.5.7.3.1"
                }
                Add-Content $certCfg "[Extensions]"
                Add-Content $certCfg $san
                Add-Content $certCfg "Critical=2.5.29.17"

                if ($PScmdlet.ShouldProcess("local", "Creating certificate for $computer")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Running: certreq -q -new $certCfg $certCsr"
                    $create = certreq -q -new $certCfg $certCsr
                }

                if ($SelfSigned) {
                    $serial = (($create -Split "Serial Number:" -Split "Subject")[2]).Trim() # D:
                    $storedCert = Get-ChildItem Cert:\LocalMachine\My -Recurse | Where-Object SerialNumber -eq $serial

                    # certreq installs a self-signed certificate twice: with its key in LocalMachine\My, and without the key in
                    # LocalMachine\CA, the intermediate CA store. The copy serves no purpose, a self-signed certificate is its own
                    # root, and it stays behind when the certificate is removed later. So it goes right away.
                    if ($storedCert) {
                        $caStore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList "CA", "LocalMachine"
                        $caStore.Open("ReadWrite")
                        foreach ($caCopy in $caStore.Certificates.Find("FindByThumbprint", $storedCert.Thumbprint, $false)) {
                            $caStore.Remove($caCopy)
                        }
                        $caStore.Close()
                    }

                    if ($computer.IsLocalHost) {
                        $storedCert | Select-Object * | Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
                    }
                } else {
                    if ($PScmdlet.ShouldProcess("local", "Submitting certificate request for $computer to $CaServer\$CaName")) {
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "certreq -q -submit -config `"$CaServer\$CaName`" -attrib $certTemplate $certCsr $certCrt $certPfx"
                        $submit = certreq -q -submit -config "$CaServer\$CaName" -attrib $certTemplate $certCsr $certCrt $certPfx
                    }

                    if ($submit -match "ssued") {
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "certreq -q -accept -machine $certCrt"
                        $null = certreq -q -accept -machine $certCrt
                        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 ($certCrt, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
                        $storedCert = Get-ChildItem "Cert:\$store\$folder" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                    } elseif ($submit) {
                        Write-Message -Level Warning -Message "Something went wrong"
                        Write-Message -Level Warning -Message "$create"
                        Write-Message -Level Warning -Message "$submit"
                        # The CA did not issue the certificate, so the pending request and its key would stay in
                        # LocalMachine\REQUEST forever. They go with the failure.
                        # Other requests may have been created in the meantime by someone else, so only the request of this
                        # call goes: the one whose public key is in the request file certreq wrote. Every request has its own key.
                        $pendingRequests = @()
                        if (Test-Path -Path $certCsr) {
                            $requestFileBase64 = (Get-Content -Path $certCsr | Where-Object { $PSItem -notmatch "^-----" }) -join ""
                            $requestFileHex = [System.BitConverter]::ToString([System.Convert]::FromBase64String($requestFileBase64))
                            $pendingRequests = @(Get-ChildItem -Path Cert:\LocalMachine\REQUEST -ErrorAction SilentlyContinue | Where-Object { $requestFileHex.Contains([System.BitConverter]::ToString($PSItem.PublicKey.EncodedKeyValue.RawData)) } | ForEach-Object { $PSItem.Thumbprint })
                        }
                        foreach ($pendingRequest in $pendingRequests) {
                            Write-Message -Level Verbose -Message "Removing the pending request $pendingRequest and its key from LocalMachine\REQUEST"
                            $splatRemoveRequest = @{
                                Thumbprint      = $pendingRequest
                                Folder          = "REQUEST"
                                DeleteKey       = $true
                                Confirm         = $false
                                EnableException = $true
                            }
                            try {
                                $null = Remove-DbaComputerCertificate @splatRemoveRequest
                            } catch {
                                Write-Message -Level Warning -Message "The pending request $pendingRequest could not be removed from LocalMachine\REQUEST: $PSItem"
                            }
                        }
                        Stop-Function -Message "Failure when attempting to create the cert on $computer. $($submit | Select-Object -Last 1)" -Target $computer -Continue
                    }

                    if ($Computer.IsLocalHost) {
                        $storedCert | Select-Object * | Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
                    }
                }
            }

            if (-not $Computer.IsLocalHost) {

                if (-not $secondaryNode) {
                    if ($PScmdlet.ShouldProcess("local", "Generating pfx and reading from disk")) {
                        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Exporting PFX with password to $tempPfx"
                        $certdata = $storedCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::PFX, $SecurePassword)
                    }

                    if ($PScmdlet.ShouldProcess("local", "Removing cert from disk but keeping it in memory")) {
                        # The certificate now lives in the PFX data and belongs to the target computer. Removing only the store entry
                        # would leave its private key on this computer, so the key is deleted with it.
                        $splatRemoveLocal = @{
                            Thumbprint      = $storedCert.Thumbprint
                            DeleteKey       = $true
                            Confirm         = $false
                            EnableException = $true
                        }
                        try {
                            $localRemoval = Remove-DbaComputerCertificate @splatRemoveLocal
                            if ($localRemoval.PrivateKey -ne "Deleted") {
                                Write-Message -Level Warning -Message "The private key of the certificate $($storedCert.Thumbprint) is still on $env:COMPUTERNAME: $($localRemoval.PrivateKey)"
                            }
                        } catch {
                            # The PFX data is there, so the import on the target still goes ahead.
                            Write-Message -Level Warning -Message "The certificate $($storedCert.Thumbprint) could not be removed from LocalMachine\My on $env:COMPUTERNAME: $PSItem"
                        }
                    }

                    if ($ClusterInstanceName) { $secondaryNode = $true }
                }

                $scriptBlock = {
                    param (
                        $CertificateData,
                        [SecureString]$SecurePassword,
                        $Store,
                        $Folder,
                        $flags
                    )
                    Write-Verbose -Message "Importing cert to $Folder\$Store using flags: $flags"

                    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificateData, $SecurePassword, $flags)
                    $certstore = New-Object System.Security.Cryptography.X509Certificates.X509Store($Folder, $Store)
                    $certstore.Open('ReadWrite')
                    $certstore.Add($cert)
                    $certstore.Close()
                    Get-ChildItem "Cert:\$($Store)\$($Folder)" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                }

                if ($PScmdlet.ShouldProcess($computer, "Attempting to import new cert")) {
                    if ($flags -contains "UserProtected" -and -not $computer.IsLocalHost) {
                        Stop-Function -Message "UserProtected flag is only valid for localhost because it causes a prompt, skipping for $computer" -Continue
                    }
                    try {
                        $thumbprint = (Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $certdata, $SecurePassword, $Store, $Folder, $flags -ScriptBlock $scriptBlock -ErrorAction Stop -Verbose).Thumbprint
                        Get-DbaComputerCertificate -ComputerName $computer -Credential $Credential -Thumbprint $thumbprint
                    } catch {
                        Stop-Function -Message "Issue importing new cert on $computer" -ErrorRecord $_ -Target $computer -Continue
                    }
                }
            }
            if ($PScmdlet.ShouldProcess("local", "Removing all files from $certDir")) {
                try {
                    Remove-Item -Force -Recurse $certDir -ErrorAction SilentlyContinue
                } catch {
                    Stop-Function -Message "Issue removing files from $certDir" -Target $certDir -ErrorRecord $PSItem
                }
            }
            Write-ProgressHelper -Completed
        }
    }
}