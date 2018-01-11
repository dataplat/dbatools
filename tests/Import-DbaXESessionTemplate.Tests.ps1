$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    AfterAll {
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Profiler TSQL Duration' | Stop-DbaXESession | Remove-DbaXESession
    }
    Context "Test Importing Session Template" {
        $results = Import-DbaXESessionTemplate -SqlInstance $script:instance2 -Template 'Profiler TSQL Duration' | Start-DbaXESession
        It "session imports and is running" {
            $results.Name | Should Be "Profiler TSQL Duration"
            $results.Status | Should Be "Running"
        }
    }
}