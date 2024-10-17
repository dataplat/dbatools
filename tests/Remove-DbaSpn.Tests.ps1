param($ModuleName = 'dbatools')

Describe "Remove-DbaSpn" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaSpn
        }
        It "Accepts SPN as a parameter" {
            $CommandUnderTest | Should -HaveParameter SPN -Type String
        }
        It "Accepts ServiceAccount as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServiceAccount -Type String
        }
        It "Accepts Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Accepts EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
        It "Accepts WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type Switch
        }
        It "Accepts Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type Switch
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
