param($ModuleName = 'dbatools')

Describe "Remove-DbaAgentSchedule Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgentSchedule
        }
        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Schedule",
                "ScheduleUid",
                "Id",
                "InputObject",
                "EnableException",
                "Force",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }
}

Describe "Remove-DbaAgentSchedule Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $start = (Get-Date).AddDays(2).ToString('yyyyMMdd')
        $end = (Get-Date).AddDays(4).ToString('yyyyMMdd')

        foreach ($FrequencySubdayType in ('Time', 'Seconds', 'Minutes', 'Hours')) {
            $variables = @{
                SqlInstance                = $global:instance2
                Schedule                   = "dbatoolsci_$FrequencySubdayType"
                FrequencyRecurrenceFactor  = '1'
                FrequencySubdayInterval    = '1'
                FrequencySubdayType        = $FrequencySubdayType
                StartDate                  = $start
                StartTime                  = '010000'
                EndDate                    = $end
                EndTime                    = '020000'
            }
            $null = New-DbaAgentSchedule @variables
        }
    }

    Context "Should remove schedules" {
        It "Should find all created schedules" {
            $results = Get-DbaAgentSchedule -SqlInstance $global:instance2 | Where-Object { $_.name -like 'dbatools*' }
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should remove dbatoolsci_Minutes schedule" {
            Remove-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule dbatoolsci_Minutes -Confirm:$false
            $results = Get-DbaAgentSchedule -SqlInstance $global:instance2 -Schedule dbatoolsci_Minutes
            $results | Should -BeNullOrEmpty
        }

        It "Should remove all remaining created schedules" {
            Get-DbaAgentSchedule -SqlInstance $global:instance2 | Where-Object { $_.name -like 'dbatools*' } | Remove-DbaAgentSchedule -Confirm:$false -Force
            $results = Get-DbaAgentSchedule -SqlInstance $global:instance2 | Where-Object { $_.name -like 'dbatools*' }
            $results | Should -BeNullOrEmpty
        }
    }
}
