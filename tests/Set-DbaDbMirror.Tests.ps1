param($ModuleName = 'dbatools')

Describe "Set-DbaDbMirror" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbMirror
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have Partner parameter" {
            $CommandUnderTest | Should -HaveParameter Partner -Type String -Not -Mandatory
        }
        It "Should have Witness parameter" {
            $CommandUnderTest | Should -HaveParameter Witness -Type String -Not -Mandatory
        }
        It "Should have SafetyLevel parameter" {
            $CommandUnderTest | Should -HaveParameter SafetyLevel -Type String -Not -Mandatory
        }
        It "Should have State parameter" {
            $CommandUnderTest | Should -HaveParameter State -Type String -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
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
