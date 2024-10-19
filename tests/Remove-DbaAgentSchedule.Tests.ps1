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
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Schedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schedule
        }
        It "Should have ScheduleUid as a parameter" {
            $CommandUnderTest | Should -HaveParameter ScheduleUid
        }
        It "Should have Id as a parameter" {
            $CommandUnderTest | Should -HaveParameter Id
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force
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
