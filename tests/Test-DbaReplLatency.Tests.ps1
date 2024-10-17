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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have PublicationName parameter" {
            $CommandUnderTest | Should -HaveParameter PublicationName -Type Object[]
        }
        It "Should have TimeToLive parameter" {
            $CommandUnderTest | Should -HaveParameter TimeToLive -Type Int32
        }
        It "Should have RetainToken parameter" {
            $CommandUnderTest | Should -HaveParameter RetainToken -Type SwitchParameter
        }
        It "Should have DisplayTokenHistory parameter" {
            $CommandUnderTest | Should -HaveParameter DisplayTokenHistory -Type SwitchParameter
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    # Add more contexts and tests as needed for the specific functionality of Test-DbaReplLatency
}
