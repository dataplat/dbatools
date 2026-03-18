#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
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
