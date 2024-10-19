param($ModuleName = 'dbatools')

Describe "Get-DbaSsisEnvironmentVariable" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSsisEnvironmentVariable
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Environment as a parameter" {
            $CommandUnderTest | Should -HaveParameter Environment
        }
        It "Should have EnvironmentExclude as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnvironmentExclude
        }
        It "Should have Folder as a parameter" {
            $CommandUnderTest | Should -HaveParameter Folder
        }
        It "Should have FolderExclude as a parameter" {
            $CommandUnderTest | Should -HaveParameter FolderExclude
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
