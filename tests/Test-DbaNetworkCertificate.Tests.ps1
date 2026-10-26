#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-DbaNetworkCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Thumbprint",
                "MinimumValidDays",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Configured certificate validity" {
        It "Should treat a configured certificate that is not valid yet as invalid" {
            $futureThumbprint = "0123456789ABCDEF0123456789ABCDEF01234567"

            Mock Get-DbaNetworkConfiguration {
                [PSCustomObject]@{
                    ComputerName        = "sql1"
                    InstanceName        = "MSSQLSERVER"
                    SqlInstance         = "sql1"
                    Certificate         = [PSCustomObject]@{
                        Thumbprint = "0123456789ABCDEF0123456789ABCDEF01234567"
                        Generated  = (Get-Date).AddDays(1)
                        Expires    = (Get-Date).AddDays(30)
                    }
                    SuitableCertificate = @()
                }
            } -ModuleName dbatools

            $results = Test-DbaNetworkCertificate -SqlInstance "sql1"

            $results.ConfiguredCertificateValid | Should -Be $false
            $results.ConfiguredCertificateThumbprint | Should -Be $futureThumbprint
        }

        It "Should treat a configured certificate with missing validity dates as invalid" {
            Mock Get-DbaNetworkConfiguration {
                [PSCustomObject]@{
                    ComputerName        = "sql1"
                    InstanceName        = "MSSQLSERVER"
                    SqlInstance         = "sql1"
                    Certificate         = [PSCustomObject]@{
                        Thumbprint = "89ABCDEF0123456789ABCDEF0123456789ABCDEF"
                        Generated  = $null
                        Expires    = (Get-Date).AddDays(30)
                    }
                    SuitableCertificate = @()
                }
            } -ModuleName dbatools

            $results = Test-DbaNetworkCertificate -SqlInstance "sql1"

            $results.ConfiguredCertificateValid | Should -Be $false
            $results.ConfiguredCertificateDaysValid | Should -BeGreaterThan 0
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Way One - checking configured and available certificates" {
        BeforeAll {
            $results = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "Should return a result" {
            $results | Should -Not -Be $null
        }

        It "Should have the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "ConfiguredCertificateDaysValid",
                "ConfiguredCertificateExpires",
                "ConfiguredCertificateThumbprint",
                "ConfiguredCertificateValid",
                "InstanceName",
                "SqlInstance",
                "SuitableCertificateAvailable",
                "SuitableCertificateCount",
                "SuitableCertificates"
            )
            ($results.PsObject.Properties.Name | Sort-Object) | Should -BeExactly ($expectedProps | Sort-Object)
        }
    }

    Context "Way Two - testing a specific certificate by thumbprint" {
        BeforeAll {
            $computerName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).ComputerName
            $certificate = New-DbaComputerCertificate -ComputerName $computerName -SelfSigned -KeyLength 2048 -HashAlgorithm Sha256 -EnableException
            $results = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceSingle -Thumbprint $certificate.Thumbprint -EnableException
        }

        AfterAll {
            $null = Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $certificate.Thumbprint -EnableException
        }

        It "Should return a result" {
            $results | Should -Not -Be $null
        }

        It "Should find the certificate and report suitability" {
            $results.CertificateFound | Should -Be $true
            $results.Thumbprint | Should -Be $certificate.Thumbprint
        }

        It "Reports the legacy CSP key of New-DbaComputerCertificate as a key exchange key" {
            $results.PrivateKeyValid | Should -BeTrue
            $results.PrivateKeyProvider | Should -Be "Microsoft RSA SChannel Cryptographic Provider"
            $results.PrivateKeyNumber | Should -Be "Exchange"
        }

        It "Should have the expected properties" {
            $expectedProps = @(
                "CertificateFound",
                "ComputerName",
                "DaysValid",
                "DnsNames",
                "DnsNamesValid",
                "EnhancedKeyUsageList",
                "EnhancedKeyUsageValid",
                "InstanceName",
                "IsSuitable",
                "KeyUsages",
                "KeyUsagesValid",
                "NotAfter",
                "NotBefore",
                "PrivateKeyNumber",
                "PrivateKeyProvider",
                "PrivateKeyType",
                "PrivateKeyValid",
                "PublicKeyAlgorithm",
                "PublicKeySize",
                "PublicKeyValid",
                "SignatureAlgorithm",
                "SignatureAlgorithmValid",
                "SqlInstance",
                "Thumbprint",
                "ValidityPeriodOk"
            )
            ($results.PsObject.Properties.Name | Sort-Object) | Should -BeExactly ($expectedProps | Sort-Object)
        }
    }

    Context "Way Two - private key types" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # New-SelfSignedCertificate creates a Key Storage Provider (CNG) key by default. SQL Server loads such a key,
            # so the certificate has to count as suitable. A legacy CSP key created for signing only (KeySpec AT_SIGNATURE)
            # is the one key type the Microsoft certificate requirements rule out, so that one has to fail the check.
            # Both certificates are issued for the network name of the instance so that only the private key decides.
            $computerName = ([DbaInstanceParameter]$TestConfig.InstanceSingle).ComputerName
            $vsName = (Get-DbaNetworkConfiguration -SqlInstance $TestConfig.InstanceSingle -OutputType Certificate).VSName
            $newSelfSignedCertificate = {
                param ($Options)
                $networkName = if ($Options.VsName) { $Options.VsName } else { hostname }
                $dnsName = @()
                try {
                    $dnsName += [System.Net.Dns]::GetHostEntry($networkName).HostName
                } catch {
                    # Without a DNS entry the short name alone satisfies the DNS name check.
                }
                $dnsName += $networkName
                $splatCertificate = @{
                    DnsName           = $dnsName | Select-Object -Unique
                    CertStoreLocation = "Cert:\LocalMachine\My"
                    FriendlyName      = $Options.FriendlyName
                    KeyAlgorithm      = "RSA"
                    KeyLength         = 2048
                    HashAlgorithm     = "SHA256"
                    KeyUsage          = "DigitalSignature", "KeyEncipherment"
                    TextExtension     = @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")
                    Provider          = $Options.Provider
                }
                if ($Options.KeySpec) {
                    $splatCertificate.KeySpec = $Options.KeySpec
                }
                (New-SelfSignedCertificate @splatCertificate).Thumbprint
            }

            $kspOptions = @{
                FriendlyName = "dbatoolsci_ksp_key"
                VsName       = $vsName
                Provider     = "Microsoft Software Key Storage Provider"
            }
            $splatCreateKsp = @{
                ComputerName = $computerName
                ScriptBlock  = $newSelfSignedCertificate
                ArgumentList = $kspOptions
                # Raw, because Invoke-Command2 otherwise wraps the string in an object that only has a Length.
                Raw          = $true
            }
            $kspThumbprint = Invoke-Command2 @splatCreateKsp

            $signatureOptions = @{
                FriendlyName = "dbatoolsci_csp_signature_key"
                VsName       = $vsName
                Provider     = "Microsoft Enhanced RSA and AES Cryptographic Provider"
                KeySpec      = "Signature"
            }
            $splatCreateSignature = @{
                ComputerName = $computerName
                ScriptBlock  = $newSelfSignedCertificate
                ArgumentList = $signatureOptions
                Raw          = $true
            }
            $signatureThumbprint = Invoke-Command2 @splatCreateSignature

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $kspThumbprint, $signatureThumbprint
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Accepts a Key Storage Provider key" {
            $results = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceSingle -Thumbprint $kspThumbprint
            $results.PrivateKeyValid | Should -BeTrue
            $results.PrivateKeyProvider | Should -Be "Microsoft Software Key Storage Provider"
            $results.PrivateKeyNumber | Should -BeNullOrEmpty
            $results.IsSuitable | Should -BeTrue
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Rejects a legacy CSP key created for signing only" {
            $results = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceSingle -Thumbprint $signatureThumbprint
            $results.PrivateKeyValid | Should -BeFalse
            $results.PrivateKeyProvider | Should -Be "Microsoft Enhanced RSA and AES Cryptographic Provider"
            $results.PrivateKeyNumber | Should -Be "Signature"
            $results.IsSuitable | Should -BeFalse
            $WarnVar | Should -BeNullOrEmpty
        }
    }
}