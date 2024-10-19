param($ModuleName = 'dbatools')

Describe "Test-DbaConnectionAuthScheme" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaConnectionAuthScheme
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Kerberos as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Kerberos
        }
        It "Should have Ntlm as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Ntlm
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
