param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentJobStep" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentJobStep
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type System.Object[]
        }
        It "Should have StepName as a parameter" {
            $CommandUnderTest | Should -HaveParameter StepName -Type System.String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
        It "Should have WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type System.Management.Automation.SwitchParameter
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
