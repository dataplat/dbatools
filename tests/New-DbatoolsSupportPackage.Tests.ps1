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
            $CommandUnderTest | Should -HaveParameter Path -Type String -Mandatory:$false
        }
        It "Should have Variables as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Variables -Type String[] -Mandatory:$false
        }
        It "Should have PassThru as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter PassThru -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
        It "Should have WhatIf as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type Switch -Mandatory:$false
        }
        It "Should have Confirm as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type Switch -Mandatory:$false
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
