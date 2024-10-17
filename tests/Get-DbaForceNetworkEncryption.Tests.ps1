param($ModuleName = 'dbatools')

Describe "Get-DbaForceNetworkEncryption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaForceNetworkEncryption
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        Context "Integration Tests" -Skip:($null -ne $env:appveyor) {
            BeforeAll {
                $results = Get-DbaForceNetworkEncryption -SqlInstance $global:instance1 -EnableException
            }

            It "returns true or false" {
                $results.ForceEncryption | Should -Not -BeNullOrEmpty
            }
        }
    }
}
