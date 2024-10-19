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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "Store",
                "Folder",
                "Type",
                "Path",
                "Thumbprint",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
