param($ModuleName = 'dbatools')

Describe "Remove-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaXESmartTarget
        }
        It "Accepts InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Accepts EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
        It "Accepts Verbose as a parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Not -Mandatory
        }
        It "Accepts Debug as a parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Not -Mandatory
        }
        It "Accepts ErrorAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
        }
        It "Accepts WarningAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
        }
        It "Accepts InformationAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
        }
        It "Accepts ProgressAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
        }
        It "Accepts ErrorVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
        }
        It "Accepts WarningVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
        }
        It "Accepts InformationVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
        }
        It "Accepts OutVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
        }
        It "Accepts OutBuffer as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
        }
        It "Accepts PipelineVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
        }
        It "Accepts WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type Switch -Not -Mandatory
        }
        It "Accepts Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type Switch -Not -Mandatory
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
