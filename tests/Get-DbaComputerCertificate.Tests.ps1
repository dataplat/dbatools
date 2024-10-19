param($ModuleName = 'dbatools')

Describe "Get-DbaComputerCertificate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaComputerCertificate
        }
        It "Should have ComputerName as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Store as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Store
        }
        It "Should have Folder as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Folder
        }
        It "Should have Type as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have Path as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have Thumbprint as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Thumbprint
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path $global:appveyorlabrepo\certificates\localhost.crt -Confirm:$false
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }
        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $thumbprint -Confirm:$false
        }

        It "returns a single certificate with a specific thumbprint" {
            $cert = Get-DbaComputerCertificate -Thumbprint $thumbprint
            $cert.Thumbprint | Should -Be $thumbprint
        }

        It "returns all certificates and at least one has the specified thumbprint" {
            $certs = Get-DbaComputerCertificate
            $certs.Thumbprint | Should -Contain $thumbprint
        }

        It "returns all certificates and at least one has the specified EnhancedKeyUsageList" {
            $certs = Get-DbaComputerCertificate
            $certs.EnhancedKeyUsageList | Should -Contain '1.3.6.1.5.5.7.3.1'
        }
    }
}
