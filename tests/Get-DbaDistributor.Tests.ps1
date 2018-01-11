$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "ensuring accuracy of results" {
        $results = Get-DbaDistributor -SqlInstance $script:instance1
        It "accurately reports that the distributor is not installed" {
            $results.DistributorInstalled | Should Be $false
        }
    }
}
