$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaWaitStatistic).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Threshold', 'IncludeIgnorable', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
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
        $ignoredWaits = 'REQUEST_FOR_DEADLOCK_SEARCH', 'SLEEP_MASTERDBREADY', 'SLEEP_TASK', 'LAZYWRITER_SLEEP'
        $results = Get-DbaWaitStatistic -SqlInstance $script:instance2 -Threshold 100 -IncludeIgnorable | Where-Object {
            $ignoredWaits -contains $_.WaitType
        }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "results includes ignorable column" {
            $results[0].PSObject.Properties.Name.Contains('Ignorable') | Should Be $true
        }

        foreach ($result in $results) {
            It "returns a hyperlink" {
                $result.URL -match 'sqlskills.com' | Should Be $true
            }
        }
    }
}