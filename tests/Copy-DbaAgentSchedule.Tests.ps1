param($ModuleName = 'dbatools')

Describe "Copy-DbaAgentSchedule" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaAgentSchedule
        }

        $params = @(
            "Source",
            "SourceSqlCredential",
            "Destination",
            "DestinationSqlCredential",
            "Schedule",
            "Id",
            "InputObject",
            "Force",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
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

        It "Copies Agent Schedule" {
            $results = Copy-DbaAgentSchedule -Source $global:instance2 -Destination $global:instance3
            $results.Count | Should -BeGreaterThan 1
            ($results | Where-Object Status -eq "Successful") | Should -Not -BeNullOrEmpty
        }

        It "Returns one result of Start Time 1:00 AM" {
            $results = Get-DbaAgentSchedule -SqlInstance $global:instance3 -Schedule dbatoolsci_DailySchedule
            $results.ActiveStartTimeOfDay | Should -Be '01:00:00'
        }
    }
}
