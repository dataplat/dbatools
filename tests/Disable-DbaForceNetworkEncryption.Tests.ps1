param($ModuleName = 'dbatools')

Describe "Disable-DbaForceNetworkEncryption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaForceNetworkEncryption
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

    Context "Integration Tests" {
        BeforeAll {
            $results = Disable-DbaForceNetworkEncryption -SqlInstance $global:instance1 -EnableException
        }

        It "returns false" {
            $results.ForceEncryption | Should -Be $false
        }
    }
}
