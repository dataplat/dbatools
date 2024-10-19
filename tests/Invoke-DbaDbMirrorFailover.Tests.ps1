param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbMirrorFailover" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbMirrorFailover
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.Database[]" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Force as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Add any necessary setup code here
        }

        It "Should do something" {
            # Add actual test cases here
            $true | Should -Be $true
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
