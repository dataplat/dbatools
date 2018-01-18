$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "executes and returns the accurate info" {
        It -Skip "returns a CurrentRunStatus of Idle" {
            $agent = Get-DbaAgentJob -SqlInstance $script:instance2 -Job 'DatabaseBackup - SYSTEM_DATABASES - FULL' | Start-DbaAgentJob | Stop-DbaAgentJob
            $results.CurrentRunStatus -eq 'Idle' | Should Be $true
        }
    }
}