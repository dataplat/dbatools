param($ModuleName = 'dbatools')

Describe "Start-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaXESmartTarget
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
        It "Should have Session parameter" {
            $CommandUnderTest | Should -HaveParameter Session
        }
        It "Should have FailOnProcessingError parameter" {
            $CommandUnderTest | Should -HaveParameter FailOnProcessingError
        }
        It "Should have Responder parameter" {
            $CommandUnderTest | Should -HaveParameter Responder
        }
        It "Should have Template parameter" {
            $CommandUnderTest | Should -HaveParameter Template
        }
        It "Should have NotAsJob parameter" {
            $CommandUnderTest | Should -HaveParameter NotAsJob
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
