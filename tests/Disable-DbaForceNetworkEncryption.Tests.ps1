param($ModuleName = 'dbatools')

Describe "Disable-DbaForceNetworkEncryption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaForceNetworkEncryption
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $results = Disable-DbaForceNetworkEncryption -SqlInstance $global:instance1 -EnableException
        }

        It "returns false" {
            $results.ForceEncryption | Should -Be $false
        }
    }
}
