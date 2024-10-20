$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ExcludeJob', 'ExcludeDisabledJobs', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Gets a job step" {
        BeforeAll {
            $jobName = "dbatoolsci_job_$(get-random)"
            $null = New-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName
            $null = New-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job $jobName -StepName dbatoolsci_jobstep1 -Subsystem TransactSql -Command 'select 1'
        }
        AfterAll {
            $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName -Confirm:$false
        }

        It "Successfully gets job when not using Job param" {
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.instance2
            $results.Name | should contain 'dbatoolsci_jobstep1'
        }
        It "Successfully gets job when using Job param" {
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -Job $jobName
            $results.Name | should contain 'dbatoolsci_jobstep1'
        }
        It "Successfully gets job when excluding some jobs" {
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -ExcludeJob 'syspolicy_purge_history'
            $results.Name | should contain 'dbatoolsci_jobstep1'
        }
        It "Successfully excludes disabled jobs" {
            $null = Set-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job $jobName -Disabled
            $results = Get-DbaAgentJobStep -SqlInstance $TestConfig.instance2 -ExcludeDisabledJobs
            $results.Name | should not contain 'dbatoolsci_jobstep1'
        }

    }
}
