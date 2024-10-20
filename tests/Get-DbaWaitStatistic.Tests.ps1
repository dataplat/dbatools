param($ModuleName = 'dbatools')

Describe "Get-DbaWaitStatistic" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaWaitStatistic
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Threshold",
            "IncludeIgnorable",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaWaitStatistic -SqlInstance $global:instance2 -Threshold 100
        }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "returns a hyperlink for each result" {
            $results | ForEach-Object {
                $_.URL | Should -Match 'sqlskills.com'
            }
        }
    }

    Context "Command returns proper info when using parameter IncludeIgnorable" {
        BeforeAll {
            $ignoredWaits = 'REQUEST_FOR_DEADLOCK_SEARCH', 'SLEEP_MASTERDBREADY', 'SLEEP_TASK', 'LAZYWRITER_SLEEP'
            $results = Get-DbaWaitStatistic -SqlInstance $global:instance2 -Threshold 100 -IncludeIgnorable | Where-Object {
                $ignoredWaits -contains $_.WaitType
            }
        }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "results includes ignorable column" {
            $results[0].PSObject.Properties.Name | Should -Contain 'Ignorable'
        }

        It "returns a hyperlink for each result" {
            $results | ForEach-Object {
                $_.URL | Should -Match 'sqlskills.com'
            }
        }
    }
}
