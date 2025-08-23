function New-DbaComputerCertificateSigningRequest {
    <#
    .SYNOPSIS
        Generates certificate signing requests for SQL Server instances to enable SSL/TLS encryption and connection security.

    .DESCRIPTION
        Creates certificate signing requests (CSRs) that can be submitted to your Certificate Authority to obtain SSL/TLS certificates for SQL Server instances. This eliminates the manual process of creating certificate requests and ensures proper configuration for SQL Server's encryption requirements.

        The function generates both the certificate configuration file (.inf) and the signing request file (.csr) with proper Subject Alternative Names (SAN) to support SQL Server's certificate validation. This is essential when implementing Force Encryption, configuring encrypted connections, or meeting compliance requirements that mandate encrypted database communications.

        Supports both standalone SQL Server instances and cluster configurations, automatically resolving FQDNs and configuring appropriate DNS entries. The generated certificates work with SQL Server's encryption features including encrypted client connections, mirroring, and backup encryption scenarios.

        By default, creates RSA certificates with 1024-bit keys, though this can be customized for stronger encryption requirements. All certificates are configured as machine certificates with the Microsoft RSA SChannel Cryptographic Provider for compatibility with SQL Server's encryption stack.

    .PARAMETER ComputerName
        The target computer name hosting the SQL Server instance where the certificate will be installed. Accepts multiple computer names for batch processing.
        For standalone servers, this creates certificates for the specified machine. For clusters, specify each cluster node here and use ClusterInstanceName for the virtual cluster name.

    .PARAMETER Credential
        Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER Path
        Directory where the certificate configuration (.inf) and signing request (.csr) files will be created. Defaults to the dbatools export path.
        Each computer gets its own subdirectory containing the certificate files needed for submission to your Certificate Authority.

    .PARAMETER ClusterInstanceName
        Specifies the virtual cluster name for SQL Server failover cluster instances. This becomes the certificate's Common Name (CN) and primary DNS entry.
        Required when generating certificates for clustered SQL Server instances to ensure proper SSL validation during failovers between cluster nodes.

    .PARAMETER FriendlyName
        Sets a descriptive name for the certificate that appears in the Windows Certificate Store. Defaults to "SQL Server".
        This name helps administrators identify the certificate's purpose when managing multiple certificates on the same server.

    .PARAMETER KeyLength
        Specifies the RSA key length in bits for the certificate. Defaults to 1024 for compatibility, though 2048 or 4096 is recommended for production.
        Higher key lengths provide stronger encryption but may impact SQL Server connection performance on older hardware.

    .PARAMETER Dns
        Additional DNS names to include in the certificate's Subject Alternative Name (SAN) field. By default includes both short and FQDN names.
        Add extra DNS entries here if clients connect using aliases, load balancer names, or other DNS records that point to your SQL Server instance.

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
        https://dbatools.io/New-DbaComputerCertificateSigningRequest

    .EXAMPLE
        PS C:\> New-DbaComputerCertificateSigningRequest

        Creates a computer certificate signing request for the local machine with the keylength of 1024.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificateSigningRequest -ComputerName Server1

        Creates a computer certificate signing request for server1 with the keylength of 1024.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificateSigningRequest -ComputerName sqla, sqlb -ClusterInstanceName sqlcluster -KeyLength 4096

        Creates a computer certificate signing request for sqlcluster with the keylength of 4096.

    .EXAMPLE
        PS C:\> New-DbaComputerCertificateSigningRequest -ComputerName Server1 -WhatIf

        Shows what would happen if the command were run
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [string]$ClusterInstanceName,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [string]$FriendlyName = "SQL Server",
        [int]$KeyLength = 1024,
        [string[]]$Dns,
        [switch]$EnableException
    )
    begin {
        $englishCodes = 9, 1033, 2057, 3081, 4105, 5129, 6153, 7177, 8201, 9225
        if ($englishCodes -notcontains (Get-DbaCmObject -ClassName Win32_OperatingSystem).OSLanguage) {
            Stop-Function -Message "Currently, this command is only supported in English OS locales. OS Locale detected: $([System.Globalization.CultureInfo]::GetCultureInfo([int](Get-DbaCmObject Win32_OperatingSystem).OSLanguage).DisplayName)`nWe apologize for the inconvenience and look into providing universal language support in future releases."
            return
        }

        function GetHexLength {
            [cmdletbinding()]
            param(
                [int]$strLen
            )
            $hex = [String]::Format("{0:X2}", $strLen)

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
    }

    process {
        if (Test-FunctionInterrupt) {
            return
        }

        if (-not (Test-ElevationRequirement -ComputerName $env:COMPUTERNAME)) {
            return
        }

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

                $certDir = "$Path\$fqdn"
                $certCfg = "$certDir\request.inf"
                $certCsr = "$certDir\$fqdn.csr"

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
                Add-Content $certCfg "KeySpec = 1"
                Add-Content $certCfg "KeyLength = $KeyLength"
                Add-Content $certCfg "Exportable = TRUE"
                Add-Content $certCfg "MachineKeySet = TRUE"
                Add-Content $certCfg "FriendlyName=""$FriendlyName"""
                Add-Content $certCfg "SMIME = False"
                Add-Content $certCfg "PrivateKeyArchive = FALSE"
                Add-Content $certCfg "UserProtected = FALSE"
                Add-Content $certCfg "UseExistingKeySet = FALSE"
                Add-Content $certCfg "ProviderName = ""Microsoft RSA SChannel Cryptographic Provider"""
                Add-Content $certCfg "ProviderType = 12"
                if ($SelfSigned) {
                    Add-Content $certCfg "RequestType = Cert"
                } else {
                    Add-Content $certCfg "RequestType = PKCS10"
                }
                Add-Content $certCfg "KeyUsage = 0xa0"
                Add-Content $certCfg "[EnhancedKeyUsageExtension]"
                Add-Content $certCfg "OID=1.3.6.1.5.5.7.3.1"
                Add-Content $certCfg "[Extensions]"
                Add-Content $certCfg $san
                Add-Content $certCfg "Critical=2.5.29.17"


                if ($PScmdlet.ShouldProcess("local", "Creating certificate for $computer")) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Running: certreq -new $certCfg $certCsr"
                    $null = certreq -new $certCfg $certCsr
                }
                Get-ChildItem $certCfg, $certCsr
            }
        }
    }
}