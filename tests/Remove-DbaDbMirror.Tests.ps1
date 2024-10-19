param($ModuleName = 'dbatools')

Describe "Remove-DbaDbMirror" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbMirror
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have WhatIf as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Should have Confirm as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
