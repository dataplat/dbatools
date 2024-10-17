param($ModuleName = 'dbatools')

Describe "Set-DbaEndpoint" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaEndpoint
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Endpoint parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint -Type String[]
        }
        It "Should have Owner parameter" {
            $CommandUnderTest | Should -HaveParameter Owner -Type String
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String
        }
        It "Should have AllEndpoints parameter" {
            $CommandUnderTest | Should -HaveParameter AllEndpoints -Type SwitchParameter
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Endpoint[]
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }
}
