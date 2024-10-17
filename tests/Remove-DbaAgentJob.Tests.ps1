param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentJob Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentJob
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Job as a parameter" {
            $CommandUnderTest | Should -HaveParameter Job -Type Object[] -Mandatory:$false
        }
        It "Should have KeepHistory as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter KeepHistory -Type switch -Mandatory:$false
        }
        It "Should have KeepUnusedSchedule as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter KeepUnusedSchedule -Type switch -Mandatory:$false
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Job[] -Mandatory:$false
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
        }
    }
}

Describe "Remove-DbaAgentJob Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Command removes jobs" {
        BeforeAll {
            $null = New-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_daily -FrequencyType Daily -FrequencyInterval Everyday -Force
            $null = New-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob -Schedule dbatoolsci_daily
            $null = New-DbaAgentJobStep -SqlInstance $global:instance3 -Job dbatoolsci_testjob -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command 'select 1'
            $null = Start-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob
        }
        AfterAll {
            if (Get-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_daily) {
                Remove-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_daily -Confirm:$false
            }
        }
        It "Should have deleted job: dbatoolsci_testjob" {
            Remove-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob -Confirm:$false
            Get-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob | Should -BeNullOrEmpty
        }
        It "Should have deleted schedule: dbatoolsci_daily" {
            Get-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_daily | Should -BeNullOrEmpty
        }
        It "Should have deleted history: dbatoolsci_daily" {
            Get-DbaAgentJobHistory -SqlInstance $global:instance3 -Job dbatoolsci_testjob | Should -BeNullOrEmpty
        }
    }

    Context "Command removes job but not schedule" {
        BeforeAll {
            $null = New-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_weekly -FrequencyType Weekly -FrequencyInterval Everyday -Force
            $null = New-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob_schedule -Schedule dbatoolsci_weekly
            $null = New-DbaAgentJobStep -SqlInstance $global:instance3 -Job dbatoolsci_testjob_schedule -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command 'select 1'
        }
        AfterAll {
            if (Get-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_weekly) {
                Remove-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_weekly -Confirm:$false
            }
        }
        It "Should have deleted job: dbatoolsci_testjob_schedule" {
            Remove-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob_schedule -KeepUnusedSchedule -Confirm:$false
            Get-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob_schedule | Should -BeNullOrEmpty
        }
        It "Should not have deleted schedule: dbatoolsci_weekly" {
            Get-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_weekly | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command removes job but not history and supports piping" {
        BeforeAll {
            $jobId = New-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob_history | Select-Object -ExpandProperty JobId
            $null = New-DbaAgentJobStep -SqlInstance $global:instance3 -Job dbatoolsci_testjob_history -StepId 1 -StepName dbatoolsci_step1 -Subsystem TransactSql -Command 'select 1'
            $null = Start-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob_history
            $server = Connect-DbaInstance -SqlInstance $global:instance3
        }
        It "Should have deleted job: dbatoolsci_testjob_history" {
            Get-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob_history | Remove-DbaAgentJob -KeepHistory -Confirm:$false
            Get-DbaAgentJob -SqlInstance $global:instance3 -Job dbatoolsci_testjob_history | Should -BeNullOrEmpty
        }
        It "Should not have deleted history: dbatoolsci_testjob_history" -Skip {
            $server.Query("select 1 from sysjobhistory where job_id = '$jobId'", "msdb") | Should -Not -BeNullOrEmpty
        }
        AfterAll {
            $server.Query("delete from sysjobhistory where job_id = '$jobId'", "msdb")
        }
    }
} # $global:instance2 for appveyor
