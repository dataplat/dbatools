$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "executes and returns the accurate info" {
        $results = Get-DbaAgentJob -SqlInstance $script:instance2 -Job 'DatabaseBackup - SYSTEM_DATABASES - FULL' | Start-DbaAgentJob
        It -Skip "returns a CurrentRunStatus of not Idle" {
            $null = Get-DbaAgentJob -SqlInstance $script:instance2 -Job 'DatabaseBackup - SYSTEM_DATABASES - FULL' | Stop-DbaAgentJob
            $results.CurrentRunStatus -ne 'Idle' | Should Be $true
        }
    }
}