$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Schedule', 'Id', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = New-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_MonthlyTest -FrequencyType Monthly -FrequencyInterval 10 -FrequencyRecurrenceFactor 1 -Force
        $null = New-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_WeeklyTest -FrequencyType Weekly -FrequencyInterval 2 -FrequencyRecurrenceFactor 1 -StartTime 020000  -Force
    }
    Afterall {
        $schedules = Get-DbaAgentSchedule -SqlInstance $script:instance2 -schedule dbatoolsci_WeeklyTest, dbatoolsci_MonthlyTest
        $Schedules.DROP()
    }

    Context "Gets the list of Schedules" {
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2
        It "Results are not empty" {
            $results | Should Not BeNullOrEmpty
        }
    }

    Context "Monthly schedule is correct" {
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 -Schedule dbatoolsci_MonthlyTest
        It "Should  get one schedule" {
            $results.count | Should Be 1
        }
        It "Results are not empty" {
            $results | Should Not BeNullOrEmpty
        }
        It "Should have the name MonthlyTest" {
            $results.ScheduleName | Should Be "dbatoolsci_MonthlyTest"
        }
        It "Should have a frequency of 10" {
            $results.FrequencyInterval | Should Be 10
        }
        It "Should be enabled" {
            $results.IsEnabled | Should Be $true
        }
        It "SqlInstance should not be null" {
            $results.SqlInstance | Should Not BeNullOrEmpty
        }
        It "Should have correct description" {
            $datetimeFormat = (Get-culture).DateTimeFormat
            $startDate = Get-Date $results.ActiveStartDate -format $datetimeFormat.ShortDatePattern
            $results.Description | Should Be "Occurs every month on day 10 of that month at 12:00:00 AM. Schedule will be used starting on $startDate."
        }
    }
}