param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceAuditSpecification" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceAuditSpecification
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
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
