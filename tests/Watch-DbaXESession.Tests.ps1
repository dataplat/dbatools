param($ModuleName = 'dbatools')

Describe "Watch-DbaXESession" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Watch-DbaXESession
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Session",
            "InputObject",
            "Raw",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
