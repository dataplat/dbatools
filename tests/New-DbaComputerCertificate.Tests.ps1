param($ModuleName = 'dbatools')

Describe "New-DbaComputerCertificate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaComputerCertificate
        }
        $requiredParameters = @(
            "ComputerName",
            "Credential",
            "CaServer",
            "CaName",
            "ClusterInstanceName",
            "SecurePassword",
            "FriendlyName",
            "CertificateTemplate",
            "KeyLength",
            "Store",
            "Folder",
            "Flag",
            "Dns",
            "SelfSigned",
            "EnableException",
            "HashAlgorithm",
            "MonthsValid"
        )
        It "has the required parameter: <_>" -ForEach $requiredParameters {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "New-DbaComputerCertificate Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $env:skipIntegrationTests = $env:appveyor -eq $true
    }

    Context "Can generate a new certificate" -Skip:$env:skipIntegrationTests {
        BeforeAll {
            $cert = New-DbaComputerCertificate -SelfSigned -EnableException
        }
        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $cert.Thumbprint -Confirm:$false
        }
        It "returns the right EnhancedKeyUsageList" {
            "$($cert.EnhancedKeyUsageList)" | Should -Match '1\.3\.6\.1\.5\.5\.7\.3\.1'
        }
        It "returns the right FriendlyName" {
            $cert.FriendlyName | Should -Match 'SQL Server'
        }
        It "Returns the right default encryption algorithm" {
            $cert.SignatureAlgorithm.FriendlyName | Should -Match 'sha1RSA'
        }
        It "Returns the right default one year expiry date" {
            $cert.NotAfter | Should -BeGreaterThan (Get-Date).AddMonths(11)
            $cert.NotAfter | Should -BeLessThan (Get-Date).AddMonths(13)
        }
    }

    Context "Can generate a new certificate with correct settings" -Skip:$env:skipIntegrationTests {
        BeforeAll {
            $cert = New-DbaComputerCertificate -SelfSigned -HashAlgorithm "Sha256" -MonthsValid 60 -EnableException
        }
        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $cert.Thumbprint -Confirm:$false
        }
        It "Returns the right encryption algorithm" {
            $cert.SignatureAlgorithm.FriendlyName | Should -Match 'sha256RSA'
        }
        It "Returns the right five year (60 month) expiry date" {
            $cert.NotAfter | Should -BeGreaterThan (Get-Date).AddMonths(59)
            $cert.NotAfter | Should -BeLessThan (Get-Date).AddMonths(61)
        }
    }
}
