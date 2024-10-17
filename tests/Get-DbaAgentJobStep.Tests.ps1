param($ModuleName = 'dbatools')

Describe "Get-DbaAgentJobStep" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentJobStep
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type String[]
        }
        It "Should have ExcludeJob as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeJob -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Job[]
        }
        It "Should have ExcludeDisabledJobs as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDisabledJobs -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Gets a job step" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $jobName = "dbatoolsci_job_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobName -StepName dbatoolsci_jobstep1 -Subsystem TransactSql -Command 'select 1'
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Confirm:$false
        }

        It "Successfully gets job when not using Job param" {
            $results = Get-DbaAgentJobStep -SqlInstance $script:instance2
            $results.Name | Should -Contain 'dbatoolsci_jobstep1'
        }
        It "Successfully gets job when using Job param" {
            $results = Get-DbaAgentJobStep -SqlInstance $script:instance2 -Job $jobName
            $results.Name | Should -Contain 'dbatoolsci_jobstep1'
        }
        It "Successfully gets job when excluding some jobs" {
            $results = Get-DbaAgentJobStep -SqlInstance $script:instance2 -ExcludeJob 'syspolicy_purge_history'
            $results.Name | Should -Contain 'dbatoolsci_jobstep1'
        }
        It "Successfully excludes disabled jobs" {
            $null = Set-DbaAgentJob -SqlInstance $script:instance2 -Job $jobName -Disabled
            $results = Get-DbaAgentJobStep -SqlInstance $script:instance2 -ExcludeDisabledJobs
            $results.Name | Should -Not -Contain 'dbatoolsci_jobstep1'
        }
    }
}
