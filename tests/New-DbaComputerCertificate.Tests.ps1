param($ModuleName = 'dbatools')

Describe "New-DbaComputerCertificate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaComputerCertificate
        }
        It "Should have ComputerName as a non-mandatory DbaInstanceParameter[] parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have CaServer as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter CaServer
        }
        It "Should have CaName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter CaName
        }
        It "Should have ClusterInstanceName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ClusterInstanceName
        }
        It "Should have SecurePassword as a non-mandatory SecureString parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword
        }
        It "Should have FriendlyName as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter FriendlyName
        }
        It "Should have CertificateTemplate as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter CertificateTemplate
        }
        It "Should have KeyLength as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter KeyLength
        }
        It "Should have Store as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Store
        }
        It "Should have Folder as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Folder
        }
        It "Should have Flag as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Flag
        }
        It "Should have Dns as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Dns
        }
        It "Should have SelfSigned as a non-mandatory Switch parameter" {
            $CommandUnderTest | Should -HaveParameter SelfSigned
        }
        It "Should have EnableException as a non-mandatory Switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have HashAlgorithm as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter HashAlgorithm
        }
        It "Should have MonthsValid as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter MonthsValid
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
