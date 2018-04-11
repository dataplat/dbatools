$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"


Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
    }
    AfterAll {
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
    }
    Context "Test Importing Session Template" {
        $results = Import-DbaXESessionTemplate -SqlInstance $script:instance2 -Template 'Profiler TSQL Duration'
        
        It "session should exist" {
            $results.Name | Should Be 'Profiler TSQL Duration'
        }
        
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
        $results = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Profiler TSQL Duration'
        
        It "session should no longer exist" {
            $results.Name | Should Be $null
            $results.Status | Should Be $null
        }
    }
}