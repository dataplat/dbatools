param($ModuleName = 'dbatools')

Describe "Get-DbaPbmCategorySubscription" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmCategorySubscription
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    # Add more contexts here for additional tests
    # For example:
    # Context "Command Execution" {
    #     BeforeAll {
    #         # Setup code, if needed
    #     }
    #     It "Should return expected results" {
    #         # Test code
    #     }
    # }
}
