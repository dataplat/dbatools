param($ModuleName = 'dbatools')

Describe "Get-DbaConnection" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaConnection
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $results = Get-DbaConnection -SqlInstance $global:instance1
        }

        It "Returns the proper authentication scheme" {
            foreach ($result in $results) {
                $result.AuthScheme | Should -BeIn @('ntlm', 'Kerberos')
            }
        }
    }
}
