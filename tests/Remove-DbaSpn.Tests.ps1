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
        It "Accepts Verbose as a parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch
        }
        It "Accepts Debug as a parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch
        }
        It "Accepts ErrorAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference
        }
        It "Accepts WarningAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference
        }
        It "Accepts InformationAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference
        }
        It "Accepts ProgressAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference
        }
        It "Accepts ErrorVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String
        }
        It "Accepts WarningVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String
        }
        It "Accepts InformationVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String
        }
        It "Accepts OutVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String
        }
        It "Accepts OutBuffer as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32
        }
        It "Accepts PipelineVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String
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
