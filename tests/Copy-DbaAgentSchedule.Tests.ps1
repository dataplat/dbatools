#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaAgentSchedule" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaAgentSchedule
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "Source",
                "SourceSqlCredential",
                "Destination", 
                "DestinationSqlCredential",
                "Schedule",
                "Id",
                "InputObject",
                "Force",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaAgentSchedule" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $sql = "EXEC msdb.dbo.sp_add_schedule @schedule_name = N'dbatoolsci_DailySchedule' , @freq_type = 4, @freq_interval = 1, @active_start_time = 010000"
        $server.Query($sql)
    }

    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $sql = "EXEC msdb.dbo.sp_delete_schedule @schedule_name = 'dbatoolsci_DailySchedule'"
        $server.Query($sql)

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        $sql = "EXEC msdb.dbo.sp_delete_schedule @schedule_name = 'dbatoolsci_DailySchedule'"
        $server.Query($sql)
    }

    Context "When copying agent schedule between instances" {
        BeforeAll {
            $results = Copy-DbaAgentSchedule -Source $TestConfig.instance2 -Destination $TestConfig.instance3
        }

        It "Returns more than one result" {
            $results.Count | Should -BeGreaterThan 1
        }

        It "Contains at least one successful copy" {
            $results | Where-Object Status -eq "Successful" | Should -Not -BeNullOrEmpty
        }

        It "Creates schedule with correct start time" {
            $schedule = Get-DbaAgentSchedule -SqlInstance $TestConfig.instance3 -Schedule dbatoolsci_DailySchedule
            $schedule.ActiveStartTimeOfDay | Should -Be '01:00:00'
        }
    }
}
