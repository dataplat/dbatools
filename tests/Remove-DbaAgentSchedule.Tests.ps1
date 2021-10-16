$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Schedule', 'ScheduleUid', 'id', 'InputObject', 'EnableException', 'Force'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $start = (Get-Date).AddDays(2).ToString('yyyyMMdd')
        $end = (Get-Date).AddDays(4).ToString('yyyyMMdd')

        foreach ($FrequencySubdayType in ('Time', 'Seconds', 'Minutes', 'Hours')) {
            $variables = @{SqlInstance    = $script:instance2
                Schedule                  = "dbatoolsci_$FrequencySubdayType"
                FrequencyRecurrenceFactor = '1'
                FrequencySubdayInterval   = '1'
                FrequencySubdayType       = $FrequencySubdayType
                StartDate                 = $start
                StartTime                 = '010000'
                EndDate                   = $end
                EndTime                   = '020000'
            }
            $null = New-DbaAgentSchedule @variables
        }
    }

    Context "Should remove schedules" {
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object { $_.name -like 'dbatools*' }
        It "Should find all created schedule" {
            $results | Should Not BeNullOrEmpty
        }

        $null = Remove-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_Minutes -Confirm:$false
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_Minutes
        It "Should not find dbatoolsci_Minutes" {
            $results | Should BeNullOrEmpty
        }

        $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object { $_.name -like 'dbatools*' } | Remove-DbaAgentSchedule -Confirm:$false -Force
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object { $_.name -like 'dbatools*' }
        It "Should not find any created schedule" {
            $results | Should BeNullOrEmpty
        }
    }
}