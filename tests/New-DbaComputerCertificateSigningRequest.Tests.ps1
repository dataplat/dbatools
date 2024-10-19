param($ModuleName = 'dbatools')

Describe "New-DbaComputerCertificateSigningRequest" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaComputerCertificateSigningRequest
        }
        It "Should have ComputerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have ClusterInstanceName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ClusterInstanceName
        }
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have FriendlyName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter FriendlyName
        }
        It "Should have KeyLength as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter KeyLength
        }
        It "Should have Dns as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Dns
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        It "generates a new certificate" {
            $files = New-DbaComputerCertificateSigningRequest
            $files.Count | Should -Be 2
            $files | Remove-Item -Confirm:$false
        }
    }
}
