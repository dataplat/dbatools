param($ModuleName = 'dbatools')

Describe "Remove-DbaCmConnection" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaCmConnection
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Should have Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
