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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Kerberos as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Kerberos -Type switch
        }
        It "Should have Ntlm as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Ntlm -Type switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch
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
