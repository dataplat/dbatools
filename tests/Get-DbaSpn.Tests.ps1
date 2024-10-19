param($ModuleName = 'dbatools')

Describe "Get-DbaSpn" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSpn
        }
        It "Accepts ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Accepts AccountName as a parameter" {
            $CommandUnderTest | Should -HaveParameter AccountName
        }
        It "Accepts Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Accepts EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    # Add more contexts and tests as needed for integration testing
    # For example:
    # Context "Integration Tests" {
    #     BeforeAll {
    #         # Setup code for integration tests
    #     }
    #
    #     It "Should return valid SPNs" {
    #         # Test code
    #     }
    #
    #     AfterAll {
    #         # Cleanup code for integration tests
    #     }
    # }
}
