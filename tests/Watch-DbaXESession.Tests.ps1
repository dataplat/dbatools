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
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Session parameter" {
            $CommandUnderTest | Should -HaveParameter Session
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Raw parameter" {
            $CommandUnderTest | Should -HaveParameter Raw
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command functions as expected" {
        BeforeAll {
            $global:instanceNotSupported = $true
        }

        It "warns if SQL instance version is not supported" {
            Mock Connect-DbaInstance {
                [PSCustomObject]@{
                    Version = New-Object System.Version(10, 0, 0, 0)
                }
            }

            $warningMessage = ""
            $null = Watch-DbaXESession -SqlInstance $global:instance1 -Session system_health -WarningAction SilentlyContinue -WarningVariable warningMessage

            $warningMessage | Should -Match "SQL Server version 11 required"
        }
    }
}
