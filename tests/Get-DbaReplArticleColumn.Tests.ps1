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
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Mandatory:$false
        }
        It "Should have Publication as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter Publication -Type Object[] -Mandatory:$false
        }
        It "Should have Article as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Article -Type String[] -Mandatory:$false
        }
        It "Should have Column as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Column -Type String[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
