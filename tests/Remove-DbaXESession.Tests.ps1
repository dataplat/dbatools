$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    AfterAll {
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session db_ola_health | Remove-DbaXESession
    }
    Context "Test Importing Session Template" {
        $results = Import-DbaXESessionTemplate -SqlInstance $script:instance2 -Template db_ola_health

        It "session should exist" {
            $results.Name | Should Be "db_ola_health"
        }

        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session db_ola_health | Remove-DbaXESession
        $results = Get-DbaXESession -SqlInstance $script:instance2 -Session db_ola_health
        It "session should no longer exist" {
            $results.Name | Should Be $null
            $results.Status | Should Be $null
        }
    }
}