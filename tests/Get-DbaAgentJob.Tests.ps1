$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Count Number of Database Maintenance Agent Jobs on localhost" {
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 | Where-Object Category -EQ 'Database Maintenance'
        It "Should report the right number of SQL Agent jobs associated to the Database Maintenance category" {
            $results.Count | Should Be 11
        }
    }

}
