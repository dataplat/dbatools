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
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential
        }
        It "Should have Schedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schedule
        }
        It "Should have Id as a parameter" {
            $CommandUnderTest | Should -HaveParameter Id
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
