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
            $certificate = New-DbaComputerCertificate -ComputerName $TestConfig.InstanceSingle -SelfSigned -KeyLength 2048 -HashAlgorithm Sha256 -EnableException
            $results = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceSingle -Thumbprint $certificate.Thumbprint -EnableException
        }

        AfterAll {
            $null = Remove-DbaComputerCertificate -Thumbprint $certificate.Thumbprint -EnableException
        }

        It "Should return a result" {
            $results | Should -Not -Be $null
        }

        It "Should find the certificate and report suitability" {
            $results.CertificateFound | Should -Be $true
            $results.Thumbprint | Should -Be $certificate.Thumbprint
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
}