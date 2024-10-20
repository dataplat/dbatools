param($ModuleName = 'dbatools')

Describe "Get-DbaPbmCategorySubscription" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmCategorySubscription
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
