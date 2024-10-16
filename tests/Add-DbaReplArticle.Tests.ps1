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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have Publication parameter" {
            $CommandUnderTest | Should -HaveParameter Publication -Type String
        }
        It "Should have Schema parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String
        }
        It "Should have Name parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String
        }
        It "Should have Filter parameter" {
            $CommandUnderTest | Should -HaveParameter Filter -Type String
        }
        It "Should have CreationScriptOptions parameter" {
            $CommandUnderTest | Should -HaveParameter CreationScriptOptions -Type PSObject
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
