param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentJobStep" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentJobStep
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type Object[]
        }
        It "Should have StepName as a parameter" {
            $CommandUnderTest | Should -HaveParameter StepName -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
        It "Should have WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type Switch
        }
        It "Should have Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type Switch
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
