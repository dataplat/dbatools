param($ModuleName = 'dbatools')

Describe "Test-DbaReplLatency" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaReplLatency
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have PublicationName parameter" {
            $CommandUnderTest | Should -HaveParameter PublicationName
        }
        It "Should have TimeToLive parameter" {
            $CommandUnderTest | Should -HaveParameter TimeToLive
        }
        It "Should have RetainToken parameter" {
            $CommandUnderTest | Should -HaveParameter RetainToken
        }
        It "Should have DisplayTokenHistory parameter" {
            $CommandUnderTest | Should -HaveParameter DisplayTokenHistory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    # Add more contexts and tests as needed for the specific functionality of Test-DbaReplLatency
}
