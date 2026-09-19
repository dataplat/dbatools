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

#Tests do not run in appveyor
Describe $CommandName -Tag IntegrationTests -Skip:([bool]$env:appveyor) {
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
}

# Unlike the Describe above, the provider assertions run on the Azure lane as well: creating a self-signed certificate
# in LocalMachine\My works on the runners, and the provider of the key has to be verified for real there.
Describe $CommandName -Tag IntegrationTests {
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
            $remoteKspCert = New-DbaComputerCertificate -ComputerName $computerName -SelfSigned -Provider "Microsoft Software Key Storage Provider"
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
    }
}