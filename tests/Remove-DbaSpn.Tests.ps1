param($ModuleName = 'dbatools')

Describe "Remove-DbaSpn" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaSpn
        }
        It "Accepts SPN as a parameter" {
            $CommandUnderTest | Should -HaveParameter SPN
        }
        It "Accepts ServiceAccount as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServiceAccount
        }
        It "Accepts Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
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

    # Add more contexts and tests as needed for Remove-DbaSpn functionality
    # For example:
    # Context "Remove SPN" {
    #     BeforeAll {
    #         # Setup code
    #     }
    #     It "Successfully removes an SPN" {
    #         # Test code
    #     }
    #     AfterAll {
    #         # Cleanup code
    #     }
    # }
}
