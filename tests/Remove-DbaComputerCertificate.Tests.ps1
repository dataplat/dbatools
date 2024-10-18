param($ModuleName = 'dbatools')

Describe "Remove-DbaComputerCertificate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaComputerCertificate
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have Thumbprint as a parameter" {
            $CommandUnderTest | Should -HaveParameter Thumbprint -Type System.String[]
        }
        It "Should have Store as a parameter" {
            $CommandUnderTest | Should -HaveParameter Store -Type System.String
        }
        It "Should have Folder as a parameter" {
            $CommandUnderTest | Should -HaveParameter Folder -Type System.String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
