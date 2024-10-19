param($ModuleName = 'dbatools')

Describe "Show-DbaInstanceFileSystem" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Show-DbaInstanceFileSystem
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
