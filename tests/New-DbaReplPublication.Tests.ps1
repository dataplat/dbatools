param($ModuleName = 'dbatools')

Describe "New-DbaReplPublication" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaReplPublication
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
        It "Should have Name parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have LogReaderAgentCredential parameter" {
            $CommandUnderTest | Should -HaveParameter LogReaderAgentCredential
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
