param($ModuleName = 'dbatools')

Describe "Start-DbaAgentJob" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaAgentJob
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Job parameter" {
            $CommandUnderTest | Should -HaveParameter Job
        }
        It "Should have StepName parameter" {
            $CommandUnderTest | Should -HaveParameter StepName
        }
        It "Should have ExcludeJob parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJob
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have AllJobs parameter" {
            $CommandUnderTest | Should -HaveParameter AllJobs
        }
        It "Should have Wait parameter" {
            $CommandUnderTest | Should -HaveParameter Wait
        }
        It "Should have Parallel parameter" {
            $CommandUnderTest | Should -HaveParameter Parallel
        }
        It "Should have WaitPeriod parameter" {
            $CommandUnderTest | Should -HaveParameter WaitPeriod
        }
        It "Should have SleepPeriod parameter" {
            $CommandUnderTest | Should -HaveParameter SleepPeriod
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Start a job" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $jobs = "dbatoolsci_job_$(Get-Random)", "dbatoolsci_job_$(Get-Random)", "dbatoolsci_job_$(Get-Random)"
            $jobName1, $jobName2, $jobName3 = $jobs
            foreach ($job in $jobs) {
                $null = New-DbaAgentJob -SqlInstance $global:instance2, $global:instance3 -Job $job
                $null = New-DbaAgentJobStep -SqlInstance $global:instance2, $global:instance3 -Job $job -StepName "step1_$(Get-Random)" -Subsystem TransactSql -Command "WAITFOR DELAY '00:05:00'"
                $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $job -StepName "step2" -StepId 2 -Subsystem TransactSql -Command "WAITFOR DELAY '00:00:01'"
                $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $job -StepName "step3" -StepId 3 -Subsystem TransactSql -Command "SELECT 1"
            }

            $results = Get-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName1 | Start-DbaAgentJob
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $global:instance2, $global:instance3 -Job $jobs -Confirm:$false
        }

        It "returns a CurrentRunStatus of not Idle and supports pipe" {
            $results.CurrentRunStatus | Should -Not -Be 'Idle'
        }

        It "returns a CurrentRunStatus of not null and supports pipe" {
            $results.CurrentRunStatus | Should -Not -BeNullOrEmpty
        }

        It "does not run all jobs" {
            $warn = $null
            $null = Start-DbaAgentJob -SqlInstance $global:instance2 -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Match 'use one of the job'
        }

        It "returns on multiple server inputs" {
            $results2 = Start-DbaAgentJob -SqlInstance $global:instance2, $global:instance3 -Job $jobName2
            $results2.SqlInstance.Count | Should -Be 2
        }

        It "starts job at specified step" {
            $null = Start-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName3 -StepName 'step3'
            $results3 = Get-DbaAgentJobHistory -SqlInstance $global:instance2 -Job $jobName3
            $results3.SqlInstance.Count | Should -Be 2
        }

        It "do not start job if the step does not exist" {
            $results4 = Start-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName3 -StepName 'stepdoesnoteexist'
            $results4.SqlInstance.Count | Should -Be 0
        }
    }
}
