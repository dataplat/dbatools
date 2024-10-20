param($ModuleName = 'dbatools')

Describe "Get-DbaForceNetworkEncryption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaForceNetworkEncryption
        }

        $params = @(
            "SqlInstance",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
