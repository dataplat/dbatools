param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentSchedule" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentSchedule
        }
        $paramList = @(
            'Source',
            'SourceSqlCredential',
            'Destination',
            'DestinationSqlCredential',
            'Schedule',
            'Id',
            'InputObject',
            'Force',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramList {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Copies Agent Schedule" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $sql = "EXEC msdb.dbo.sp_add_schedule @schedule_name = N'dbatoolsci_DailySchedule' , @freq_type = 4, @freq_interval = 1, @active_start_time = 010000"
            $server.Query($sql)
        }

        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $sql = "EXEC msdb.dbo.sp_delete_schedule @schedule_name = 'dbatoolsci_DailySchedule'"
            $server.Query($sql)

            $server = Connect-DbaInstance -SqlInstance $global:instance3
            $sql = "EXEC msdb.dbo.sp_delete_schedule @schedule_name = 'dbatoolsci_DailySchedule'"
            $server.Query($sql)
        }

        It "returns more than one result with at least one successful" {
            $results = Copy-DbaAgentSchedule -Source $global:instance2 -Destination $global:instance3
            $results.Count | Should -BeGreaterThan 1
            $results | Where-Object Status -eq "Successful" | Should -Not -BeNullOrEmpty
        }

        It "returns one result of Start Time 1:00 AM" {
            $results = Get-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_DailySchedule
            $results.ActiveStartTimeOfDay | Should -Be '01:00:00'
        }
    }
}
