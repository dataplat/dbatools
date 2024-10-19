param($ModuleName = 'dbatools')

Describe "Remove-DbaComputerCertificate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaComputerCertificate
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "Thumbprint",
                "Store",
                "Folder",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Can remove a certificate" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $null = Add-DbaComputerCertificate -Path $env:appveyorlabrepo\certificates\localhost.crt -Confirm:$false
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }

        It "returns the correct store Name" {
            $results = Remove-DbaComputerCertificate -Thumbprint $thumbprint -Confirm:$false
            $results.Store | Should -Be "LocalMachine"
        }

        It "returns the correct folder Name" {
            $results = Remove-DbaComputerCertificate -Thumbprint $thumbprint -Confirm:$false
            $results.Folder | Should -Be "My"
        }

        It "reports the proper status of Removed" {
            $results = Remove-DbaComputerCertificate -Thumbprint $thumbprint -Confirm:$false
            $results.Status | Should -Be "Removed"
        }

        It "really removed the certificate" {
            Remove-DbaComputerCertificate -Thumbprint $thumbprint -Confirm:$false
            $results = Get-DbaComputerCertificate -Thumbprint $thumbprint
            $results | Should -BeNullOrEmpty
        }
    }
}
