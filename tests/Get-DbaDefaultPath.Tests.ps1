param($ModuleName = 'dbatools')

Describe "Get-DbaDefaultPath" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDefaultPath
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $results = Get-DbaDefaultPath -SqlInstance $global:instance1
        }

        It "Data returns a value that contains :\" {
            $results.Data | Should -Match "\:\\"
        }
        It "Log returns a value that contains :\" {
            $results.Log | Should -Match "\:\\"
        }
        It "Backup returns a value that contains :\" {
            $results.Backup | Should -Match "\:\\"
        }
        It "ErrorLog returns a value that contains :\" {
            $results.ErrorLog | Should -Match "\:\\"
        }
    }
}
