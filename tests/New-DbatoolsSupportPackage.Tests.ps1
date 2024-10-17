param($ModuleName = 'dbatools')

Describe "New-DbatoolsSupportPackage" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbatoolsSupportPackage
        }
        It "Should have Path as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Not -Mandatory
        }
        It "Should have Variables as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Variables -Type String[] -Not -Mandatory
        }
        It "Should have PassThru as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter PassThru -Type Switch -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
        It "Should have Verbose as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Not -Mandatory
        }
        It "Should have Debug as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Not -Mandatory
        }
        It "Should have ErrorAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have WarningAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have InformationAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ProgressAction as a non-mandatory ActionPreference parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ErrorVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
        }
        It "Should have WarningVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
        }
        It "Should have InformationVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
        }
        It "Should have OutVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
        }
        It "Should have OutBuffer as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
        }
        It "Should have PipelineVariable as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
        }
        It "Should have WhatIf as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type Switch -Not -Mandatory
        }
        It "Should have Confirm as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type Switch -Not -Mandatory
        }
    }

    # Add more contexts and tests as needed for integration testing
    # For example:
    # Context "Command functionality" {
    #     It "Should create a support package" {
    #         # Test implementation
    #     }
    # }
}
