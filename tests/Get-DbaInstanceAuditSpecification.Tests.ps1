param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceAuditSpecification" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceAuditSpecification
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

# Integration tests
# Add your integration tests here
# Example:
# Describe "Get-DbaInstanceAuditSpecification Integration Tests" -Tag 'IntegrationTests' {
#     BeforeAll {
#         # Setup code
#     }
#     Context "When retrieving audit specifications" {
#         It "Should return audit specifications" {
#             # Test code
#         }
#     }
#     AfterAll {
#         # Cleanup code
#     }
# }
