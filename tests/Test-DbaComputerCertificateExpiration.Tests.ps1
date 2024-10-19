param($ModuleName = 'dbatools')

Describe "Test-DbaComputerCertificateExpiration" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaComputerCertificateExpiration
        }
        It "Should have ComputerName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Store as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Store
        }
        It "Should have Folder as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Folder
        }
        It "Should have Type as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have Thumbprint as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Thumbprint
        }
        It "Should have Threshold as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Threshold
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Test-DbaComputerCertificateExpiration Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        # Run setup code to get script variables within scope of the discovery phase
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    Context "tests a certificate" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path $env:appveyorlabrepo\certificates\localhost.crt -Confirm:$false
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $thumbprint -Confirm:$false
        }

        It "reports that the certificate is expired" {
            $results = Test-DbaComputerCertificateExpiration -Thumbprint $thumbprint
            $results | Select-Object -ExpandProperty Note | Should -Be "This certificate has expired and is no longer valid"
            $results.Thumbprint | Should -Be $thumbprint
        }
    }
}
