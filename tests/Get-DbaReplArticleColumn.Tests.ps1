param($ModuleName = 'dbatools')

Describe "Get-DbaReplArticleColumn" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaReplArticleColumn
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have Publication as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Publication
        }
        It "Should have Article as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Article
        }
        It "Should have Column as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Column
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
