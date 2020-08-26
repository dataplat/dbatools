$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'InputObject', 'AllJobs', 'Wait', 'Parallel', 'WaitPeriod', 'SleepPeriod', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Start a job" {
        BeforeAll {
            $jobName = "dbatoolsci_job_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $script:instance2, $script:instance3 -Job $jobName
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2, $script:instance3 -Job $jobName -StepName dbatoolsci_jobstep1 -Subsystem TransactSql -Command "WAITFOR DELAY '00:05:00'"

            $results = Get-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName | Start-DbaAgentJob
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $script:instance2, $script:instance3 -Job $jobName -Confirm:$false
        }

        It "returns a CurrentRunStatus of not Idle and supports pipe" {
            $results.CurrentRunStatus -ne 'Idle' | Should Be $true
        }

        It "returns a CurrentRunStatus of not null and supports pipe" {
            $results.CurrentRunStatus -ne $null | Should Be $true
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