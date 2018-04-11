$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command returns proper info" {
        $results = Get-DbaWaitStatistic -SqlInstance $script:instance2 -Threshold 100

        It "returns results" {
            $results.Count -gt 0 | Should Be $true
        }

        foreach ($result in $results) {
            It "returns a hyperlink" {
                $result.URL -match 'sqlskills.com' | Should Be $true
            }
        }
    }

    Context "Command returns proper info when using parameter IncludeIgnorable" {
        $results = Get-DbaWaitStatistic -SqlInstance $script:instance2 -Threshold 100 -IncludeIgnorable | Where-Object {
                $_.WaitType -eq 'SLEEP_MASTERDBREADY'
            }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "results includes ignorable column" {
            $results.PSObject.Properties.Name.Contains('Ignorable') | Should Be $true
        }

        foreach ($result in $results) {
            It "returns a hyperlink" {
                $result.URL -match 'sqlskills.com' | Should Be $true
            }
        }
    }
}