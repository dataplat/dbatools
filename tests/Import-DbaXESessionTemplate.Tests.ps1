$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    AfterAll {
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Function Executions' | Stop-DbaXESession | Remove-DbaXESession
    }
    Context "Test Importing Session Template" {
        $results = Import-DbaXESessionTemplate -SqlInstance $script:instance2 -Template 'Function Executions' | Start-DbaXESession
        It -Skip "session imports and is running" {
            $results.Name | Should Be "Function Executions"
            $results.Status | Should Be "Running"
        }
    }
}