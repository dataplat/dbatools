param($ModuleName = 'dbatools')

Describe "Test-DbaConnectionAuthScheme" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaConnectionAuthScheme
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Kerberos",
                "Ntlm",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "returns the proper transport" {
        BeforeAll {
            $results = Test-DbaConnectionAuthScheme -SqlInstance $global:instance1
        }
        It "returns ntlm auth scheme" {
            $results.AuthScheme | Should -Be 'ntlm'
        }
    }
}
