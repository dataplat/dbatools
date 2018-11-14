$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 10
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Start-DbaAgentJob).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'InputObject', 'AllJobs', 'Wait', 'WaitPeriod', 'SleepPeriod', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    It "returns a CurrentRunStatus of not Idle and supports pipe" {
        $null = Get-DbaAgentJob -SqlInstance $script:instance2 -Job 'DatabaseBackup - SYSTEM_DATABASES - FULL' | Start-DbaAgentJob
        $results.CurrentRunStatus -ne 'Idle' | Should Be $true
    }

    It "does not run all jobs" {
        $null = Start-DbaAgentJob -SqlInstance $script:instance2 -WarningAction SilentlyContinue -WarningVariable warn
        $warn -match 'use one of the job' | Should Be $true
    }
}