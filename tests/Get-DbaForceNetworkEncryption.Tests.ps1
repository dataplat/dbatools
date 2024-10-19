param($ModuleName = 'dbatools')

Describe "Get-DbaForceNetworkEncryption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaForceNetworkEncryption
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "Credential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
