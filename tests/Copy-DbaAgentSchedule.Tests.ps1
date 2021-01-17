$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Force', 'EnableException', 'Schedule', 'Id', 'InputObject'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $sql = "EXEC msdb.dbo.sp_add_schedule @schedule_name = N'dbatoolsci_DailySchedule' , @freq_type = 4, @freq_interval = 1, @active_start_time = 010000"
        $server.Query($sql)
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $sql = "EXEC msdb.dbo.sp_delete_schedule @schedule_name = 'dbatoolsci_DailySchedule'"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $sql = "EXEC msdb.dbo.sp_delete_schedule @schedule_name = 'dbatoolsci_DailySchedule'"
        $server.Query($sql)

    }

    Context "Copies Agent Schedule" {
        $results = Copy-DbaAgentSchedule -Source $script:instance2 -Destination $script:instance3

        It "returns one results" {
            $results.Count | Should -BeGreaterThan 1
            ($results | Where-Object Status -eq "Successful") | Should -Not -Be $null
        }

        It "return one result of Start Time 1:00 AM" {
            $results = Get-DbaAgentSchedule -SqlInstance $script:instance3 -Schedule dbatoolsci_DailySchedule
            $results.ActiveStartTimeOfDay -eq '01:00:00'
        }
    }
}