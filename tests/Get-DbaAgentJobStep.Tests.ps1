param($ModuleName = 'dbatools')

Describe "Get-DbaAgentJobStep" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgentJobStep
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Job",
            "ExcludeJob",
            "InputObject"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
        $CommandUnderTest | Should -HaveParameter ExcludeDisabledJobs
        $CommandUnderTest | Should -HaveParameter EnableException
    }

    Context "Gets a job step" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $jobName = "dbatoolsci_job_$(Get-Random)"
            $null = New-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName
            $null = New-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobName -StepName dbatoolsci_jobstep1 -Subsystem TransactSql -Command 'select 1'
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName -Confirm:$false
        }

        It "Successfully gets job when not using Job param" {
            $results = Get-DbaAgentJobStep -SqlInstance $global:instance2
            $results.Name | Should -Contain 'dbatoolsci_jobstep1'
        }
        It "Successfully gets job when using Job param" {
            $results = Get-DbaAgentJobStep -SqlInstance $global:instance2 -Job $jobName
            $results.Name | Should -Contain 'dbatoolsci_jobstep1'
        }
        It "Successfully gets job when excluding some jobs" {
            $results = Get-DbaAgentJobStep -SqlInstance $global:instance2 -ExcludeJob 'syspolicy_purge_history'
            $results.Name | Should -Contain 'dbatoolsci_jobstep1'
        }
        It "Successfully excludes disabled jobs" {
            $null = Set-DbaAgentJob -SqlInstance $global:instance2 -Job $jobName -Disabled
            $results = Get-DbaAgentJobStep -SqlInstance $global:instance2 -ExcludeDisabledJobs
            $results.Name | Should -Not -Contain 'dbatoolsci_jobstep1'
        }
    }
}
