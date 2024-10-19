param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentJobStep" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentJobStep
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Job",
                "StepName",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

# Integration tests
# Add your integration tests here
# Example:
# Describe "Remove-DbaAgentJobStep Integration Tests" -Tag "IntegrationTests" {
#     BeforeAll {
#         # Setup code
#     }
#     Context "When removing a job step" {
#         It "Should remove the specified job step" {
#             # Test code
#         }
#     }
#     AfterAll {
#         # Cleanup code
#     }
# }
