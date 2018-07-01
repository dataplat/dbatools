$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    It "returns a CurrentRunStatus of not Idle and supports pipe" {
        $null = Get-DbaAgentJob -SqlInstance $script:instance2 -Job 'DatabaseBackup - SYSTEM_DATABASES - FULL' | Start-DbaAgentJob
        $results.CurrentRunStatus -ne 'Idle' | Should Be $true
    }
    
    It "does not run all jobs" {
        $null = Start-DbaAgentJob -SqlInstance $script:instance2 -WarningAction SilentlyContinue -WarningVariable warn
        $warn -match 'use one of the job' | Should Be $true
    }
}
