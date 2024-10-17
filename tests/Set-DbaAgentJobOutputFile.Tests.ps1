param($ModuleName = 'dbatools')

Describe "Set-DbaAgentJobOutputFile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgentJobOutputFile
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type Object[]
        }
        It "Should have Step as a parameter" {
            $CommandUnderTest | Should -HaveParameter Step -Type Object[]
        }
        It "Should have OutputFile as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutputFile -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
