param($ModuleName = 'dbatools')

Describe "Enable-DbaForceNetworkEncryption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaForceNetworkEncryption
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $results = Enable-DbaForceNetworkEncryption -SqlInstance $global:instance1 -EnableException
        }

        It "returns true" {
            $results.ForceEncryption | Should -Be $true
        }
    }
}
