param($ModuleName = 'dbatools')

Describe "Stop-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaXESmartTarget
        }
        It "Accepts InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Accepts EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
