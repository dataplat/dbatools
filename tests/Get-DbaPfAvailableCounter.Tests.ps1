$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'ComputerName', 'Credential', 'Pattern', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeEach {
        $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
    }
    AfterAll {
        $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
    }
    Context "Verifying command returns all the required results" {
        It "returns the correct values" {
            $results = Get-DbaPfAvailableCounter
            $results.Count -gt 1000 | Should Be $true
        }
        It "returns are pipable into Add-DbaPfDataCollectorCounter" {
            $results = Get-DbaPfAvailableCounter -Pattern *sql* | Select-Object -First 3 | Add-DbaPfDataCollectorCounter -CollectorSet 'Long Running Queries' -Collector DataCollector01 -WarningAction SilentlyContinue
            foreach ($result in $results) {
                $result.Name -match "sql" | Should Be $true
            }
        }
    }
}