$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Remove-DbaAgentJob).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'KeepHistory', 'KeepUnusedSchedule', 'Mode', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command removes jobs" {
        BeforeAll {
            $null = New-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_daily -FrequencyType Daily -FrequencyInterval Everyday -Force
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob -Schedule dbatoolsci_daily
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job dbatoolsci_testjob -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command 'select 1'
            $null = Start-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob
        }
        AfterAll {
            if (Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_daily) { Remove-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_daily }
        }
        $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob
        It "Should have deleted job: dbatoolsci_testjob" {
            (Get-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob) | Should BeNullOrEmpty
        }
        It "Should have deleted schedule: dbatoolsci_daily" {
            (Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_daily) | Should BeNullOrEmpty
        }
        It "Should have deleted history: dbatoolsci_daily" {
            (Get-DbaAgentJobHistory -SqlInstance $script:instance2 -Job dbatoolsci_testjob) | Should BeNullOrEmpty
        }
    }
    Context "Command removes job but not schedule" {
        BeforeAll {
            $null = New-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_weekly -FrequencyType Weekly -FrequencyInterval Everyday -Force
            $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_schedule -Schedule dbatoolsci_weekly
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job dbatoolsci_testjob_schedule -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command 'select 1'
        }
        AfterAll {
            if (Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_weekly) { Remove-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_weekly }
        }
        $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_schedule -KeepUnusedSchedule
        It "Should have deleted job: dbatoolsci_testjob_schedule" {
            (Get-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_schedule) | Should BeNullOrEmpty
        }
        It "Should not have deleted schedule: dbatoolsci_weekly" {
            (Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_weekly) | Should Not BeNullOrEmpty
        }
    }
    Context "Command removes job but not history" {
        BeforeAll {
            $jobId = New-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_history | Select-Object -ExpandProperty JobId
            $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job dbatoolsci_testjob_history -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command 'select 1'
            $null = Start-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_history
            $server = Connect-DbaInstance -SqlInstance $script:instance2
        }
        $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_history -KeepHistory
        It "Should have deleted job: dbatoolsci_testjob_history" {
            (Get-DbaAgentJob -SqlInstance $script:instance2 -Job dbatoolsci_testjob_history) | Should BeNullOrEmpty
        }
        It "Should not have deleted history: dbatoolsci_testjob_history" {
            ($server.Query("select 1 from sysjobhistory where job_id = '$jobId'", "msdb")) | Should Not BeNullOrEmpty
        }
        AfterAll {
            $server.Query("delete from sysjobhistory where job_id = '$jobId'", "msdb")
        }
    }
}