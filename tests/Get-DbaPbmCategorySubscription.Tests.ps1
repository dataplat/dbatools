param($ModuleName = 'dbatools')

Describe "Get-DbaPbmCategorySubscription" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmCategorySubscription
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
