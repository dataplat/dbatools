param($ModuleName = 'dbatools')

Describe "Remove-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaXESmartTarget
        }
        It "Accepts InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Accepts EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Accepts WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Accepts Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
