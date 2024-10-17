param($ModuleName = 'dbatools')

Describe "Start-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaXESmartTarget
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String -Not -Mandatory
        }
        It "Should have Session parameter" {
            $CommandUnderTest | Should -HaveParameter Session -Type String -Not -Mandatory
        }
        It "Should have FailOnProcessingError parameter" {
            $CommandUnderTest | Should -HaveParameter FailOnProcessingError -Type SwitchParameter -Not -Mandatory
        }
        It "Should have Responder parameter" {
            $CommandUnderTest | Should -HaveParameter Responder -Type Object[] -Not -Mandatory
        }
        It "Should have Template parameter" {
            $CommandUnderTest | Should -HaveParameter Template -Type String[] -Not -Mandatory
        }
        It "Should have NotAsJob parameter" {
            $CommandUnderTest | Should -HaveParameter NotAsJob -Type SwitchParameter -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
