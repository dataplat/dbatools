param($ModuleName = 'dbatools')

Describe "Enable-DbaForceNetworkEncryption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaForceNetworkEncryption
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

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $results = Enable-DbaForceNetworkEncryption -SqlInstance $global:instance1 -EnableException
        }

        It "returns true" {
            $results.ForceEncryption | Should -Be $true
        }
    }
}
