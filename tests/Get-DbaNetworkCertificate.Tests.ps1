param($ModuleName = 'dbatools')

Describe "Get-DbaNetworkCertificate" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaNetworkCertificate
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
