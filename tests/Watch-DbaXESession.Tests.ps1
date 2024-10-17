param($ModuleName = 'dbatools')

Describe "Watch-DbaXESession" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Watch-DbaXESession
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Session parameter" {
            $CommandUnderTest | Should -HaveParameter Session -Type String
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Session[]
        }
        It "Should have Raw parameter" {
            $CommandUnderTest | Should -HaveParameter Raw -Type Switch
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command functions as expected" {
        BeforeAll {
            $env:instanceNotSupported = $true
        }

        It "warns if SQL instance version is not supported" {
            Mock Connect-DbaInstance {
                [PSCustomObject]@{
                    Version = New-Object System.Version(10, 0, 0, 0)
                }
            }

            $warningMessage = ""
            $null = Watch-DbaXESession -SqlInstance $env:instance1 -Session system_health -WarningAction SilentlyContinue -WarningVariable warningMessage

            $warningMessage | Should -Match "SQL Server version 11 required"
        }
    }
}
