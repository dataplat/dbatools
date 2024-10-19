param($ModuleName = 'dbatools')

Describe "Add-DbaReplArticle" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaReplArticle
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
        It "Should have Publication parameter" {
            $CommandUnderTest | Should -HaveParameter Publication
        }
        It "Should have Schema parameter" {
            $CommandUnderTest | Should -HaveParameter Schema
        }
        It "Should have Name parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have Filter parameter" {
            $CommandUnderTest | Should -HaveParameter Filter
        }
        It "Should have CreationScriptOptions parameter" {
            $CommandUnderTest | Should -HaveParameter CreationScriptOptions
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
