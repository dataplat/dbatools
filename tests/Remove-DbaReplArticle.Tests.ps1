param($ModuleName = 'dbatools')

Describe "Remove-DbaReplArticle" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaReplArticle
        }
        It "Should have SqlInstance as a Mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter -Mandatory
        }
        It "Should have SqlCredential as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have Publication as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter Publication -Type String
        }
        It "Should have Schema as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String
        }
        It "Should have Name as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String
        }
        It "Should have InputObject as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type PSObject
        }
        It "Should have EnableException as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
