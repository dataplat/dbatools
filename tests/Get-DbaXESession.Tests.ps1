$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 4
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaXESession).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Session', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying command output" {
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $script:instance2
            $results.Count -gt 1 | Should Be $true
        }

        It "returns only the system_health session" {
            $results = Get-DbaXESession -SqlInstance $script:instance2 -Session system_health
            $results.Name -eq 'system_health' | Should Be $true
        }
    }
}