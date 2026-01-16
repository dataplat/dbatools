#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentSchedule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Schedule",
                "ScheduleUid",
                "Id",
                "InputObject",
                "EnableException",
                "Force"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $startDate = (Get-Date).AddDays(2).ToString("yyyyMMdd")
        $endDate = (Get-Date).AddDays(4).ToString("yyyyMMdd")

        foreach ($FrequencySubdayType in ("Time", "Seconds", "Minutes", "Hours")) {
            $splatSchedule = @{
                SqlInstance               = $TestConfig.InstanceSingle
                Schedule                  = "dbatoolsci_$FrequencySubdayType"
                FrequencyRecurrenceFactor = "1"
                FrequencySubdayInterval   = "1"
                FrequencySubdayType       = $FrequencySubdayType
                StartDate                 = $startDate
                StartTime                 = "010000"
                EndDate                   = $endDate
                EndTime                   = "020000"
            }
            $null = New-DbaAgentSchedule @splatSchedule
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup any remaining test schedules
        $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*" | Remove-DbaAgentSchedule -Force

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing schedules" {
        It "Should find all created schedules" {
            $results = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should remove specific schedule by name" {
            $null = Remove-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule dbatoolsci_Minutes
            $results = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle -Schedule dbatoolsci_Minutes
            $results | Should -BeNullOrEmpty
        }

        It "Should remove all remaining test schedules via pipeline" {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*" | Remove-DbaAgentSchedule -Force
            $results = Get-DbaAgentSchedule -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools*"
            $results | Should -BeNullOrEmpty
        }
    }
}