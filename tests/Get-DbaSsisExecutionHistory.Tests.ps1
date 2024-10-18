param($ModuleName = 'dbatools')

Describe "Get-DbaSsisExecutionHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSsisExecutionHistory
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Since as a parameter" {
            $CommandUnderTest | Should -HaveParameter Since -Type System.DateTime
        }
        It "Should have Status as a parameter" {
            $CommandUnderTest | Should -HaveParameter Status -Type System.String[]
        }
        It "Should have Project as a parameter" {
            $CommandUnderTest | Should -HaveParameter Project -Type System.String[]
        }
        It "Should have Folder as a parameter" {
            $CommandUnderTest | Should -HaveParameter Folder -Type System.String[]
        }
        It "Should have Environment as a parameter" {
            $CommandUnderTest | Should -HaveParameter Environment -Type System.String[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
