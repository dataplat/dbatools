param($ModuleName = 'dbatools')

Describe "Get-DbaSsisExecutionHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSsisExecutionHistory
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Since as a parameter" {
            $CommandUnderTest | Should -HaveParameter Since -Type DateTime
        }
        It "Should have Status as a parameter" {
            $CommandUnderTest | Should -HaveParameter Status -Type String[]
        }
        It "Should have Project as a parameter" {
            $CommandUnderTest | Should -HaveParameter Project -Type String[]
        }
        It "Should have Folder as a parameter" {
            $CommandUnderTest | Should -HaveParameter Folder -Type String[]
        }
        It "Should have Environment as a parameter" {
            $CommandUnderTest | Should -HaveParameter Environment -Type String[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
