param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbUpgrade" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbUpgrade
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have NoCheckDb parameter" {
            $CommandUnderTest | Should -HaveParameter NoCheckDb
        }
        It "Should have NoUpdateUsage parameter" {
            $CommandUnderTest | Should -HaveParameter NoUpdateUsage
        }
        It "Should have NoUpdateStats parameter" {
            $CommandUnderTest | Should -HaveParameter NoUpdateStats
        }
        It "Should have NoRefreshView parameter" {
            $CommandUnderTest | Should -HaveParameter NoRefreshView
        }
        It "Should have AllUserDatabases parameter" {
            $CommandUnderTest | Should -HaveParameter AllUserDatabases
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
