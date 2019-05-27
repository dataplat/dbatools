$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Schedule', 'InputObject', 'EnableException', 'Force'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
            Where-Object {$_.name -like 'dbatools*'}
        It "Should find all created schedule" {
            $results | Should Not BeNullOrEmpty
        }

        Remove-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_MonthlyRelative -Confirm:$false
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_MonthlyRelative
        It "Should not find dbatoolsci_MonthlyRelative" {
            $results | Should BeNullOrEmpty
        }

        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
            Where-Object {$_.name -like 'dbatools*'} |
            Remove-DbaAgentSchedule -Confirm:$false -Force
        It "Should not find any created schedule" {
            $results | Should BeNullOrEmpty
        }
    }
}