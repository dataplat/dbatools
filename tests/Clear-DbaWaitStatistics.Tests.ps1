$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command executes properly and returns proper info" {
        $results = Clear-DbaWaitStatistics -SqlInstance $script:instance1 -Confirm:$false

        It "returns success" {
            $results.Status -eq 'Success' | Should Be $true
        }
    }
}