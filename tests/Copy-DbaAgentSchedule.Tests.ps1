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
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Schedule as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schedule -Type String[]
        }
        It "Should have Id as a parameter" {
            $CommandUnderTest | Should -HaveParameter Id -Type Int32[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type JobSchedule[]
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
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

        It "Copies Agent Schedule" {
            $results = Copy-DbaAgentSchedule -Source $script:instance2 -Destination $script:instance3
            $results.Count | Should -BeGreaterThan 1
            ($results | Where-Object Status -eq "Successful") | Should -Not -BeNullOrEmpty
        }

        It "Returns one result of Start Time 1:00 AM" {
            $results = Get-DbaAgentSchedule -SqlInstance $script:instance3 -Schedule dbatoolsci_DailySchedule
            $results.ActiveStartTimeOfDay | Should -Be '01:00:00'
        }
    }
}
