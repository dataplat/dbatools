$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'InputObject', 'AllJobs', 'Wait', 'WaitPeriod', 'SleepPeriod', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Start a job" {
        BeforeAll {
            $jobName = "dbatoolsci_job_$(get-random)"
            $null = New-DbaAgentJob -SqlInstance $script:instance2,$script:instance3 -Job $jobName
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2,$script:instance3 -Job $jobName -StepName dbatoolsci_jobstep1 -Subsystem TransactSql -Command 'select 1'
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $script:instance2,$script:instance3 -Job $jobName -Confirm:$false
        }

        It "returns a CurrentRunStatus of not Idle and supports pipe" {
            $results = Get-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName | Start-DbaAgentJob
            $results.CurrentRunStatus -ne 'Idle' | Should Be $true
        }

        It "does not run all jobs" {
            $null = Start-DbaAgentJob -SqlInstance $script:instance2 -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match 'use one of the job' | Should Be $true
        }

        It "returns on multiple server inputs" {
            $results2 = Start-DbaAgentJob -SqlInstance $script:instance2, $script:instance3 -Job $jobName
            ($results2.SqlInstance).Count | Should -Be 2
        }
    }
}