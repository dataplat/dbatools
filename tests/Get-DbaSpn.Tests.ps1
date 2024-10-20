param($ModuleName = 'dbatools')

Describe "Get-DbaSpn" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSpn
        }

        $params = @(
            "ComputerName",
            "AccountName",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
