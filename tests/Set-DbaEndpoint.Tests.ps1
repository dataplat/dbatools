param($ModuleName = 'dbatools')

Describe "Set-DbaEndpoint" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaEndpoint
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Endpoint parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint
        }
        It "Should have Owner parameter" {
            $CommandUnderTest | Should -HaveParameter Owner
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have AllEndpoints parameter" {
            $CommandUnderTest | Should -HaveParameter AllEndpoints
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}
