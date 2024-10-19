param($ModuleName = 'dbatools')

Describe "Get-DbaSsisExecutionHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSsisExecutionHistory
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Since as a parameter" {
            $CommandUnderTest | Should -HaveParameter Since
        }
        It "Should have Status as a parameter" {
            $CommandUnderTest | Should -HaveParameter Status
        }
        It "Should have Project as a parameter" {
            $CommandUnderTest | Should -HaveParameter Project
        }
        It "Should have Folder as a parameter" {
            $CommandUnderTest | Should -HaveParameter Folder
        }
        It "Should have Environment as a parameter" {
            $CommandUnderTest | Should -HaveParameter Environment
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
