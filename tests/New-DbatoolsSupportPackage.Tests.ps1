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
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have Variables as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Variables
        }
        It "Should have PassThru as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter PassThru
        }
        It "Should have EnableException as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have WhatIf as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Should have Confirm as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
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
