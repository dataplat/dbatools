$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

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