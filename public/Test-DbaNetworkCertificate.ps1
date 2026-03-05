function Test-DbaNetworkCertificate {
    <#
    .SYNOPSIS
        Tests network certificate configuration and suitability for SQL Server instances

    .DESCRIPTION
        Tests network certificate configuration for SQL Server instances in two ways.

        Without the Thumbprint parameter (Way One): Calls Get-DbaNetworkConfiguration to retrieve
        information about the currently configured certificate and available suitable certificates.
        Returns a summary indicating whether the configured certificate is valid for the minimum
        required days and whether any suitable certificates are available.

        With the Thumbprint parameter (Way Two): Executes detailed certificate validation tests
        on the target machine to determine if the specified certificate is suitable for SQL Server
        network encryption. Returns individual test results for each requirement, making it easy
        to identify which specific tests failed.

        The certificate validation logic is aligned with Get-DbaNetworkConfiguration to ensure
        consistent behavior. For details on certificate requirements, see
        https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/certificate-requirements

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER Thumbprint
        The thumbprint of a specific certificate to test for suitability (Way Two).
        When specified, the command performs detailed validation of that certificate and returns
        individual test results for each requirement.
        When omitted, the command checks the configured certificate and available suitable
        certificates using Get-DbaNetworkConfiguration (Way One).

    .PARAMETER MinimumValidDays
        The minimum number of days the certificate must be valid from today.
        A certificate expiring within fewer than this many days will not be considered valid.
        Defaults to 0, meaning the certificate just needs to be currently valid.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Certificate, Encryption, Security, Network
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaNetworkCertificate

    .OUTPUTS
        PSCustomObject

        Without -Thumbprint (Way One), returns one object per instance with:
        - ComputerName: Computer name of the SQL Server instance
        - InstanceName: SQL Server instance name
        - SqlInstance: Full SQL Server instance name (computer\instance format)
        - ConfiguredCertificateValid: Boolean indicating if the configured certificate is valid for at least MinimumValidDays
        - ConfiguredCertificateThumbprint: Thumbprint of the configured certificate, or $null if none is configured
        - ConfiguredCertificateExpires: Expiration date of the configured certificate, or $null if none is configured
        - ConfiguredCertificateDaysValid: Number of days until the configured certificate expires, or $null if none is configured
        - SuitableCertificateAvailable: Boolean indicating if at least one suitable certificate is available for the minimum valid days
        - SuitableCertificateCount: Number of suitable certificates available for the minimum valid days
        - SuitableCertificates: Array of suitable certificate objects (Thumbprint, FriendlyName, NotBefore, NotAfter, DaysValid)

        With -Thumbprint (Way Two), returns one object per instance with:
        - ComputerName: Computer name of the SQL Server instance
        - InstanceName: SQL Server instance name
        - SqlInstance: Full SQL Server instance name (computer\instance format)
        - Thumbprint: The thumbprint of the tested certificate
        - IsSuitable: Boolean indicating if the certificate passes all validation tests
        - CertificateFound: Boolean indicating if the certificate was found in LocalMachine\My
        - KeyUsagesValid: Boolean indicating if the certificate has the required key usages (DigitalSignature and KeyEncipherment)
        - DnsNamesValid: Boolean indicating if the certificate's DNS names include the server's network name
        - PrivateKeyValid: Boolean indicating if the private key is RSACryptoServiceProvider with KeyNumber Exchange
        - PublicKeyValid: Boolean indicating if the public key is RSA with at least 2048 bits
        - SignatureAlgorithmValid: Boolean indicating if the signature algorithm is SHA-256, SHA-384, or SHA-512
        - EnhancedKeyUsageValid: Boolean indicating if the certificate has the Server Authentication enhanced key usage
        - ValidityPeriodOk: Boolean indicating if the certificate is currently valid and valid for at least MinimumValidDays
        - KeyUsages: The actual key usage flags value
        - DnsNames: Array of DNS names from the certificate
        - PrivateKeyType: Full type name of the private key object
        - PrivateKeyNumber: Key number from the CspKeyContainerInfo
        - PublicKeySize: Public key size in bits
        - PublicKeyAlgorithm: Public key algorithm friendly name
        - SignatureAlgorithm: Signature algorithm friendly name
        - EnhancedKeyUsageList: Array of enhanced key usage friendly names
        - NotBefore: Certificate validity start date
        - NotAfter: Certificate validity end date (expiration)
        - DaysValid: Number of days until the certificate expires

    .EXAMPLE
        PS C:\> Test-DbaNetworkCertificate -SqlInstance sql2019

        Tests the configured network certificate for the default instance on sql2019.
        Returns whether the configured certificate is valid and whether suitable certificates are available.

    .EXAMPLE
        PS C:\> Test-DbaNetworkCertificate -SqlInstance sql2019 -MinimumValidDays 30

        Tests the network certificate configuration for sql2019, requiring certificates to be valid
        for at least 30 more days.

    .EXAMPLE
        PS C:\> Test-DbaNetworkCertificate -SqlInstance sql2019 -Thumbprint 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2

        Tests whether the certificate with the given thumbprint is suitable for SQL Server network
        encryption on sql2019. Returns detailed test results for each requirement.

    .EXAMPLE
        PS C:\> Test-DbaNetworkCertificate -SqlInstance sql2019 -Thumbprint 1223FB1ACBCA44D3EE9640F81B6BA14A92F3D6E2 -MinimumValidDays 30

        Tests whether the certificate is suitable for sql2019 and will remain valid for at least 30 days.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [string]$Thumbprint,
        [int]$MinimumValidDays = 0,
        [switch]$EnableException
    )

    begin {
        # This scriptblock is used for Way Two: detailed validation of a specific certificate by thumbprint.
        # The validation logic is aligned with the suitable certificate check in Get-DbaNetworkConfiguration.
        # For details on the requirements see https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/certificate-requirements
        $scriptBlock = {
            $instance = $args[0]
            $thumbprint = $args[1]
            $minimumValidDays = $args[2]

            # As we go remote, ensure the assembly is loaded
            [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
            $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
            $null = $wmi.Initialize()
            $wmiService = $wmi.Services | Where-Object { $_.DisplayName -eq "SQL Server ($($instance.InstanceName))" }
            $vsname = ($wmiService.AdvancedProperties | Where-Object Name -eq VSNAME).Value
            if ([System.String]::IsNullOrEmpty($vsname)) {
                # Fallback for some WMI versions where direct property access fails (aligned with Get-DbaNetworkConfiguration)
                $vsnameRaw = $wmiService.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }
                if (![System.String]::IsNullOrEmpty($vsnameRaw)) {
                    $vsname = ($vsnameRaw -Split 'Value\=')[1]
                }
            }

            # Determine the network name used for DNS name validation (aligned with Get-DbaNetworkConfiguration)
            $networkName = if ($vsname) { $vsname } else { hostname }

            # Find the certificate by thumbprint in LocalMachine\My
            $cert = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object Thumbprint -eq $thumbprint

            if ($null -eq $cert) {
                [PSCustomObject]@{
                    ComputerName            = $instance.ComputerName
                    InstanceName            = $instance.InstanceName
                    SqlInstance             = $instance.SqlFullName.Trim('[]')
                    Thumbprint              = $thumbprint
                    IsSuitable              = $false
                    CertificateFound        = $false
                    KeyUsagesValid          = $null
                    DnsNamesValid           = $null
                    PrivateKeyValid         = $null
                    PublicKeyValid          = $null
                    SignatureAlgorithmValid = $null
                    EnhancedKeyUsageValid   = $null
                    ValidityPeriodOk        = $null
                    KeyUsages               = $null
                    DnsNames                = $null
                    PrivateKeyType          = $null
                    PrivateKeyNumber        = $null
                    PublicKeySize           = $null
                    PublicKeyAlgorithm      = $null
                    SignatureAlgorithm      = $null
                    EnhancedKeyUsageList    = $null
                    NotBefore               = $null
                    NotAfter                = $null
                    DaysValid               = $null
                }
                return
            }

            # --- Certificate validation tests, aligned with Get-DbaNetworkConfiguration ---
            $requiredKeyUsages = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment

            try {
                $keyUsageExt = $cert.Extensions | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension] }
                $keyUsages = $keyUsageExt.KeyUsages
                $keyUsagesValid = ($keyUsages -band $requiredKeyUsages) -eq $requiredKeyUsages
            } catch {
                $keyUsages = $null
                $keyUsagesValid = $false
            }

            try {
                $dnsNames = $cert.DnsNameList.Unicode
                if (-not $dnsNames -and $cert.Subject -match 'CN=([^,]+)') { $dnsNames = @( $Matches[1] ) }
                $dnsNamesValid = $dnsNames -contains $networkName -or $dnsNames -contains "$networkName.$env:USERDNSDOMAIN"
            } catch {
                $dnsNames = $null
                $dnsNamesValid = $false
            }

            try {
                $privateKeyType = if ($null -ne $cert.PrivateKey) { $cert.PrivateKey.GetType().FullName } else { $null }
                $privateKeyNumber = if ($cert.PrivateKey -is [System.Security.Cryptography.RSACryptoServiceProvider]) { $cert.PrivateKey.CspKeyContainerInfo.KeyNumber } else { $null }
                $privateKeyValid = $cert.PrivateKey -is [System.Security.Cryptography.RSACryptoServiceProvider] -and
                    $cert.PrivateKey.CspKeyContainerInfo.KeyNumber -eq [System.Security.Cryptography.KeyNumber]::Exchange
            } catch {
                $privateKeyType = $null
                $privateKeyNumber = $null
                $privateKeyValid = $false
            }

            try {
                $publicKeySize = $cert.PublicKey.Key.KeySize
                $publicKeyAlgorithm = $cert.PublicKey.Oid.FriendlyName
                $publicKeyValid = $publicKeySize -ge 2048 -and $publicKeyAlgorithm -match 'RSA'
            } catch {
                $publicKeySize = $null
                $publicKeyAlgorithm = $null
                $publicKeyValid = $false
            }

            try {
                $signatureAlgorithm = $cert.SignatureAlgorithm.FriendlyName
                $signatureAlgorithmValid = $signatureAlgorithm -match 'sha256|sha384|sha512'
            } catch {
                $signatureAlgorithm = $null
                $signatureAlgorithmValid = $false
            }

            try {
                $enhancedKeyUsageList = $cert.EnhancedKeyUsageList.FriendlyName
                $enhancedKeyUsageValid = $enhancedKeyUsageList -contains 'Server Authentication'
            } catch {
                $enhancedKeyUsageList = $null
                $enhancedKeyUsageValid = $false
            }

            $validityPeriodOk = $cert.NotBefore -lt (Get-Date) -and $cert.NotAfter -gt (Get-Date).AddDays($minimumValidDays)
            $daysValid = [int]($cert.NotAfter - (Get-Date)).TotalDays

            $isSuitable = $keyUsagesValid -and $dnsNamesValid -and $privateKeyValid -and $publicKeyValid -and $signatureAlgorithmValid -and $enhancedKeyUsageValid -and $validityPeriodOk

            [PSCustomObject]@{
                ComputerName            = $instance.ComputerName
                InstanceName            = $instance.InstanceName
                SqlInstance             = $instance.SqlFullName.Trim('[]')
                Thumbprint              = $cert.Thumbprint
                IsSuitable              = $isSuitable
                CertificateFound        = $true
                KeyUsagesValid          = $keyUsagesValid
                DnsNamesValid           = $dnsNamesValid
                PrivateKeyValid         = $privateKeyValid
                PublicKeyValid          = $publicKeyValid
                SignatureAlgorithmValid = $signatureAlgorithmValid
                EnhancedKeyUsageValid   = $enhancedKeyUsageValid
                ValidityPeriodOk        = $validityPeriodOk
                KeyUsages               = $keyUsages
                DnsNames                = $dnsNames
                PrivateKeyType          = $privateKeyType
                PrivateKeyNumber        = $privateKeyNumber
                PublicKeySize           = $publicKeySize
                PublicKeyAlgorithm      = $publicKeyAlgorithm
                SignatureAlgorithm      = $signatureAlgorithm
                EnhancedKeyUsageList    = $enhancedKeyUsageList
                NotBefore               = $cert.NotBefore
                NotAfter                = $cert.NotAfter
                DaysValid               = $daysValid
            }
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            if (Test-Bound -ParameterName Thumbprint) {
                # Way Two: Detailed validation of a specific certificate by thumbprint
                try {
                    $computerName = Resolve-DbaComputerName -ComputerName $instance.ComputerName -Credential $Credential
                    $null = Test-ElevationRequirement -ComputerName $computerName -EnableException $true
                    $splatInvoke = @{
                        ScriptBlock  = $scriptBlock
                        ArgumentList = $instance, $Thumbprint, $MinimumValidDays
                        ComputerName = $computerName
                        Credential   = $Credential
                        ErrorAction  = "Stop"
                    }
                    Invoke-Command2 @splatInvoke
                } catch {
                    Stop-Function -Message "Failed to test certificate '$Thumbprint' on $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                }
            } else {
                # Way One: Check configured and available certificates using Get-DbaNetworkConfiguration
                try {
                    $splatGetConf = @{
                        SqlInstance     = $instance
                        Credential      = $Credential
                        EnableException = $true
                    }
                    $netConf = Get-DbaNetworkConfiguration @splatGetConf

                    if (-not $netConf) {
                        Stop-Function -Message "Failed to get network configuration from $($instance.ComputerName) for instance $($instance.InstanceName)." -Target $instance -Continue
                    } elseif ($netConf.Certificate -is [string]) {
                        Stop-Function -Message "Failed to collect certificate information from $($instance.ComputerName) for instance $($instance.InstanceName): $($netConf.Certificate)" -Target $instance -Continue
                    } else {
                        # Check configured certificate validity
                        $configuredThumbprint = $netConf.Certificate.Thumbprint
                        $configuredExpires = $netConf.Certificate.Expires
                        if ($configuredThumbprint) {
                            $configuredDaysValid = [int]($configuredExpires - (Get-Date)).TotalDays
                            $configuredCertificateValid = $configuredExpires -gt (Get-Date).AddDays($MinimumValidDays)
                        } else {
                            $configuredDaysValid = $null
                            $configuredCertificateValid = $false
                        }

                        # Filter suitable certificates by MinimumValidDays.
                        # Get-DbaNetworkConfiguration already filters for current validity (NotAfter > now),
                        # but we additionally filter for MinimumValidDays.
                        $suitableCerts = $netConf.SuitableCertificate | Where-Object { $_.NotAfter -gt (Get-Date).AddDays($MinimumValidDays) }
                        $suitableCertCount = ($suitableCerts | Measure-Object).Count
                        $suitableCertObjects = foreach ($cert in $suitableCerts) {
                            [PSCustomObject]@{
                                Thumbprint   = $cert.Thumbprint
                                FriendlyName = $cert.FriendlyName
                                NotBefore    = $cert.NotBefore
                                NotAfter     = $cert.NotAfter
                                DaysValid    = [int]($cert.NotAfter - (Get-Date)).TotalDays
                            }
                        }

                        [PSCustomObject]@{
                            ComputerName                    = $netConf.ComputerName
                            InstanceName                    = $netConf.InstanceName
                            SqlInstance                     = $netConf.SqlInstance
                            ConfiguredCertificateValid      = $configuredCertificateValid
                            ConfiguredCertificateThumbprint = $configuredThumbprint
                            ConfiguredCertificateExpires    = $configuredExpires
                            ConfiguredCertificateDaysValid  = $configuredDaysValid
                            SuitableCertificateAvailable    = $suitableCertCount -gt 0
                            SuitableCertificateCount        = $suitableCertCount
                            SuitableCertificates            = $suitableCertObjects
                        }
                    }
                } catch {
                    Stop-Function -Message "Failed to test network certificate for $($instance.ComputerName) instance $($instance.InstanceName)." -Target $instance -ErrorRecord $_ -Continue
                }
            }
        }
    }
}
