param($ModuleName = 'dbatools')

Describe "Test-DbaComputerCertificateExpiration" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaComputerCertificateExpiration
        }
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have Store as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Store -Type String[] -Mandatory:$false
        }
        It "Should have Folder as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Folder -Type String[] -Mandatory:$false
        }
        It "Should have Type as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Type -Type String -Mandatory:$false
        }
        It "Should have Path as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Mandatory:$false
        }
        It "Should have Thumbprint as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Thumbprint -Type String[] -Mandatory:$false
        }
        It "Should have Threshold as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter Threshold -Type Int32 -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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
