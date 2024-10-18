param($ModuleName = 'dbatools')

Describe "Remove-DbaSpn" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaSpn
        }
        It "Accepts SPN as a parameter" {
            $CommandUnderTest | Should -HaveParameter SPN -Type System.String
        }
        It "Accepts ServiceAccount as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServiceAccount -Type System.String
        }
        It "Accepts Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential
        }
        It "Accepts EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
        It "Accepts WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type System.Management.Automation.SwitchParameter
        }
        It "Accepts Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type System.Management.Automation.SwitchParameter
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
