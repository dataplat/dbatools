#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaComputerCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "CaServer",
                "CaName",
                "ClusterInstanceName",
                "SecurePassword",
                "FriendlyName",
                "CertificateTemplate",
                "KeyLength",
                "Provider",
                "Store",
                "Folder",
                "Flag",
                "Dns",
                "SelfSigned",
                "DocumentEncryptionCert",
                "EnableException",
                "HashAlgorithm",
                "MonthsValid"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "DocumentEncryptionCert validation" {
            BeforeAll {
                Mock Stop-Function { throw $Message }
            }

            It "requires SelfSigned or an explicit certificate template" {
                {
                    New-DbaComputerCertificate -DocumentEncryptionCert
                } | Should -Throw "*requires -SelfSigned or an explicit -CertificateTemplate*"
            }
        }
    }

    Context "NonExportable handling" {
        BeforeAll {
            $script:remoteFqdn = "dbatools-review-remote.example"
            $script:requestConfig = @()

            Mock Get-DbaCmObject -ModuleName "dbatools" {
                [pscustomobject]@{
                    OSLanguage = 1033
                }
            }
            Mock Resolve-DbaNetworkName -ModuleName "dbatools" {
                [pscustomobject]@{
                    Fqdn = $script:remoteFqdn
                }
            }
            Mock Test-ElevationRequirement -ModuleName "dbatools" { $true }
            Mock Set-Content -ModuleName "dbatools" {
                param($Path, $Value)
                $script:requestConfig = @($Value)
            }
            Mock Add-Content -ModuleName "dbatools" {
                param($Path, $Value)
                $script:requestConfig += $Value
            }
        }

        It "Keeps the source certificate exportable for remote installs when NonExportable is requested" {
            $splatRemoteCertificate = @{
                ComputerName = "dbatools-review-remote"
                CaServer     = "dbatools-ca"
                CaName       = "dbatools-ca"
                Flag         = "NonExportable"
                WhatIf       = $true
            }
            $null = New-DbaComputerCertificate @splatRemoteCertificate

            $script:requestConfig | Should -Contain "Exportable = TRUE"
            $script:requestConfig | Should -Not -Contain "Exportable = FALSE"
        }

        It "Writes a Key Storage Provider request when Provider asks for one" {
            $splatKspCertificate = @{
                ComputerName = "dbatools-review-remote"
                CaServer     = "dbatools-ca"
                CaName       = "dbatools-ca"
                Provider     = "Microsoft Software Key Storage Provider"
                WhatIf       = $true
            }
            $null = New-DbaComputerCertificate @splatKspCertificate

            $script:requestConfig | Should -Contain "ProviderName = ""Microsoft Software Key Storage Provider"""
            $script:requestConfig | Should -Contain "KeyAlgorithm = RSA"
            $script:requestConfig | Should -Not -Contain "KeySpec = 1"
            $script:requestConfig | Should -Not -Contain "ProviderType = 12"
        }

        It "Writes a legacy CSP request with KeySpec AT_KEYEXCHANGE by default" {
            $splatDefaultCertificate = @{
                ComputerName = "dbatools-review-remote"
                CaServer     = "dbatools-ca"
                CaName       = "dbatools-ca"
                WhatIf       = $true
            }
            $null = New-DbaComputerCertificate @splatDefaultCertificate

            $script:requestConfig | Should -Contain "ProviderName = ""Microsoft RSA SChannel Cryptographic Provider"""
            $script:requestConfig | Should -Contain "ProviderType = 12"
            $script:requestConfig | Should -Contain "KeySpec = 1"
            $script:requestConfig | Should -Not -Contain "KeyAlgorithm = RSA"
        }
    }
}

# These tests used to be skipped when APPVEYOR is set, which the Azure lanes do as well. Creating a self-signed
# certificate in LocalMachine\My works on the runners, so they run there now.
Describe $CommandName -Tag IntegrationTests {
    Context "Can generate a new certificate with default settings" {
        BeforeAll {
            $defaultCert = New-DbaComputerCertificate -SelfSigned -EnableException
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $defaultCert.Thumbprint
        }

        It "Returns the right EnhancedKeyUsageList" {
            "$($defaultCert.EnhancedKeyUsageList)" -match "1\.3\.6\.1\.5\.5\.7\.3\.1" | Should -BeTrue
        }

        It "Returns the right FriendlyName" {
            "$($defaultCert.FriendlyName)" -match "SQL Server" | Should -BeTrue
        }

        It "Returns the right default encryption algorithm" {
            "$(($defaultCert | Select-Object @{n="SignatureAlgorithm";e={$PSItem.SignatureAlgorithm.FriendlyName}})).SignatureAlgorithm)" -match "sha256RSA" | Should -BeTrue
        }

        It "Returns the right default one year expiry date" {
            $defaultCert.NotAfter -match ((Get-Date).Date).AddMonths(12) | Should -BeTrue
        }

        It "Leaves no copy of the certificate in the intermediate CA store" {
            # certreq installs a self-signed certificate a second time, without its key, in LocalMachine\CA. The command removes that copy.
            Test-Path -Path "Cert:\LocalMachine\My\$($defaultCert.Thumbprint)" | Should -BeTrue
            Test-Path -Path "Cert:\LocalMachine\CA\$($defaultCert.Thumbprint)" | Should -BeFalse
        }
    }

    Context "Can generate a new certificate with custom settings" {
        BeforeAll {
            $customCert = New-DbaComputerCertificate -SelfSigned -HashAlgorithm "Sha256" -MonthsValid 60 -EnableException
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $customCert.Thumbprint
        }

        It "Returns the right encryption algorithm" {
            "$(($customCert | Select-Object @{n="SignatureAlgorithm";e={$PSItem.SignatureAlgorithm.FriendlyName}})).SignatureAlgorithm)" -match "sha256RSA" | Should -BeTrue
        }

        It "Returns the right five year (60 month) expiry date" {
            $customCert.NotAfter -match ((Get-Date).Date).AddMonths(60) | Should -BeTrue
        }
    }

    Context "Can generate a document encryption certificate for Always Encrypted" {
        BeforeAll {
            $documentCert = New-DbaComputerCertificate -SelfSigned -DocumentEncryptionCert -EnableException
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $documentCert.Thumbprint
        }

        It "Returns the Document Encryption EKU OID" {
            "$($documentCert.EnhancedKeyUsageList)" -match "1\.3\.6\.1\.4\.1\.311\.10\.3\.11" | Should -BeTrue
        }

        It "Returns the IKE Intermediate EKU OID" {
            "$($documentCert.EnhancedKeyUsageList)" -match "1\.3\.6\.1\.5\.5\.8\.2\.2" | Should -BeTrue
        }

        It "Does not include the Server Authentication EKU OID" {
            "$($documentCert.EnhancedKeyUsageList)" -match "1\.3\.6\.1\.5\.5\.7\.3\.1" | Should -BeFalse
        }
    }

    Context "Can generate a certificate with a Key Storage Provider key" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The command returns a copy of the certificate object without the key, so the private key is read from the store entry.
            $kspCert = New-DbaComputerCertificate -SelfSigned -Provider "Microsoft Software Key Storage Provider"
            $kspStoreCert = Get-ChildItem -Path "Cert:\LocalMachine\My\$($kspCert.Thumbprint)"
            $kspKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($kspStoreCert)

            $cspCert = New-DbaComputerCertificate -SelfSigned
            $cspStoreCert = Get-ChildItem -Path "Cert:\LocalMachine\My\$($cspCert.Thumbprint)"
            $cspKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cspStoreCert)

            # For a remote computer the command exports a PFX and imports it on the target. The provider has to survive that transfer.
            # On CI the instance is local, so the transfer only happens against a lab whose instance runs on another computer.
            $computerName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).ComputerName
            $remoteIsLocal = ([DbaInstanceParameter]$TestConfig.InstanceSingle).IsLocalHost
            # The key files of this computer before the certificate for the other computer is created here. After the export
            # the certificate and its key have to be gone from this computer again.
            $keyFolders = "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys", "$env:ProgramData\Microsoft\Crypto\Keys"
            $keyFilesBefore = @((Get-ChildItem -Path $keyFolders -File).Name)
            $remoteKspCert = New-DbaComputerCertificate -ComputerName $computerName -SelfSigned -Provider "Microsoft Software Key Storage Provider"
            $keyFilesAfter = @((Get-ChildItem -Path $keyFolders -File).Name)
            $readProvider = {
                param ($Thumbprint)
                $cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$Thumbprint"
                ([System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)).Key.Provider.Provider
            }
            $splatReadProvider = @{
                ComputerName = $computerName
                ScriptBlock  = $readProvider
                ArgumentList = $remoteKspCert.Thumbprint
                # Raw, because Invoke-Command2 otherwise wraps the string in an object that only has a Length.
                Raw          = $true
            }
            $remoteProvider = Invoke-Command2 @splatReadProvider

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaComputerCertificate -Thumbprint $kspCert.Thumbprint, $cspCert.Thumbprint
            Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $remoteKspCert.Thumbprint
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Holds the private key in the Key Storage Provider" {
            $kspKey.Key.Provider.Provider | Should -Be "Microsoft Software Key Storage Provider"
            Test-Path -Path "$env:ProgramData\Microsoft\Crypto\Keys\$($kspKey.Key.UniqueName)" -PathType Leaf | Should -BeTrue
        }

        It "Holds the private key in the legacy CSP with KeySpec AT_KEYEXCHANGE by default" {
            $cspKey.Key.Provider.Provider | Should -Be "Microsoft RSA SChannel Cryptographic Provider"
            # A legacy CSP key opened through CNG reports an AT_KEYEXCHANGE KeySpec as AllUsages, an AT_SIGNATURE one as Signing.
            $cspKey.Key.KeyUsage | Should -Be "AllUsages"
            Test-Path -Path "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys\$($cspKey.Key.UniqueName)" -PathType Leaf | Should -BeTrue
        }

        It "Keeps the Key Storage Provider key when the certificate is imported on a remote computer" {
            $remoteProvider | Should -Be "Microsoft Software Key Storage Provider"
        }

        It "Leaves neither the certificate nor its key on this computer after the transfer to a remote computer" {
            if ($remoteIsLocal) {
                Set-ItResult -Skipped -Because "the instance runs on this computer, so the certificate stays here"
            }
            Test-Path -Path "Cert:\LocalMachine\My\$($remoteKspCert.Thumbprint)" | Should -BeFalse
            Test-Path -Path "Cert:\LocalMachine\CA\$($remoteKspCert.Thumbprint)" | Should -BeFalse
            $keyFilesAfter | Where-Object { $PSItem -notin $keyFilesBefore } | Should -BeNullOrEmpty
        }
    }

    Context "Leaves nothing behind when the CA does not answer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A request for a CA waits in LocalMachine\REQUEST with its key. When the CA cannot be reached the command removes
            # the request again, so the store and the key folders have to look as before.
            $requestFolders = "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys", "$env:ProgramData\Microsoft\Crypto\Keys"
            $requestsBefore = @((Get-ChildItem -Path Cert:\LocalMachine\REQUEST).Thumbprint)
            $requestKeyFilesBefore = @((Get-ChildItem -Path $requestFolders -File).Name)
            $splatUnreachableCa = @{
                CaServer        = "nosuchca.dbatools.invalid"
                CaName          = "NoSuchCA"
                WarningVariable = "unreachableCaWarning"
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            $unreachableCaResult = New-DbaComputerCertificate @splatUnreachableCa
            $requestsAfter = @((Get-ChildItem -Path Cert:\LocalMachine\REQUEST).Thumbprint)
            $requestKeyFilesAfter = @((Get-ChildItem -Path $requestFolders -File).Name)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # In case the command left the request behind after all.
            foreach ($leftover in ($requestsAfter | Where-Object { $PSItem -notin $requestsBefore })) {
                Remove-DbaComputerCertificate -Thumbprint $leftover -Folder REQUEST -DeleteKey
            }
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Warns instead of returning a certificate" {
            $unreachableCaResult | Should -BeNullOrEmpty
            # The command writes several warnings on this path, the last one is the message of Stop-Function.
            ($unreachableCaWarning -join " ") | Should -Match "Failure when attempting to create the cert"
        }

        It "Removes the pending request and its key again" {
            $requestsAfter | Where-Object { $PSItem -notin $requestsBefore } | Should -BeNullOrEmpty
            $requestKeyFilesAfter | Where-Object { $PSItem -notin $requestKeyFilesBefore } | Should -BeNullOrEmpty
        }
    }

    Context "Keeps a request of someone else when the CA does not answer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Another enrollment creates its own machine request while the command waits for the CA. Only the submission is
            # intercepted to create that request at exactly this moment; certreq, the store and the keys are real.
            $otherSubject = "CN=dbatoolsci_otherrequest_$(Get-Random)"
            $otherInf = "$([System.IO.Path]::GetTempPath())dbatoolsci_otherrequest_$(Get-Random).inf"
            $otherCsr = "$otherInf.csr"
            $otherInfContent = @"
[Version]
Signature="`$Windows NT`$"
[NewRequest]
Subject = "$otherSubject"
KeyLength = 2048
Exportable = TRUE
MachineKeySet = TRUE
ProviderName = "Microsoft Software Key Storage Provider"
KeyAlgorithm = RSA
RequestType = PKCS10
"@
            Set-Content -Path $otherInf -Value $otherInfContent
            $mockCertreq = [scriptblock]::Create(@"
if (`$args -contains "-submit") {
    `$null = certreq.exe -q -new "$otherInf" "$otherCsr"
}
certreq.exe @args
"@)
            Mock -ModuleName dbatools -CommandName certreq -MockWith $mockCertreq

            $requestsBefore = @((Get-ChildItem -Path Cert:\LocalMachine\REQUEST).Thumbprint)
            $splatUnreachableCa = @{
                CaServer        = "nosuchca.dbatools.invalid"
                CaName          = "NoSuchCA"
                WarningVariable = "otherRequestWarning"
                WarningAction   = "SilentlyContinue"
                EnableException = $false
            }
            $otherRequestResult = New-DbaComputerCertificate @splatUnreachableCa
            $newRequests = @(Get-ChildItem -Path Cert:\LocalMachine\REQUEST | Where-Object Thumbprint -notin $requestsBefore)
            $otherRequest = $newRequests | Where-Object Subject -eq $otherSubject

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            foreach ($leftover in $newRequests) {
                Remove-DbaComputerCertificate -Thumbprint $leftover.Thumbprint -Folder REQUEST -DeleteKey
            }
            Remove-Item -Path $otherInf, $otherCsr -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Warns instead of returning a certificate" {
            $otherRequestResult | Should -BeNullOrEmpty
            ($otherRequestWarning -join " ") | Should -Match "Failure when attempting to create the cert"
        }

        It "Removes only its own request" {
            $otherRequest | Should -Not -BeNullOrEmpty
            $newRequests.Count | Should -Be 1
        }

        It "Keeps the key of the other request" {
            $otherKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($otherRequest)
            $otherKey | Should -Not -BeNullOrEmpty
            # Signing needs the key file itself, the certificate only points to it.
            $otherKey.SignData([byte[]](1, 2, 3), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1) | Should -Not -BeNullOrEmpty
        }
    }
}