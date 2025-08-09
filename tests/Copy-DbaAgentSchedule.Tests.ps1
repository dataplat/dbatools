#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentSchedule",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Explain what needs to be set up for the test:
        # To test copying agent schedules, we need to create a test schedule on the source instance
        # that can be copied to the destination instance.

        # Set variables. They are available in all the It blocks.
        $scheduleName = "dbatoolsci_DailySchedule"

        # Create the test schedule on source instance
        $splatAddSchedule = @{
            SqlInstance     = $TestConfig.instance2
            EnableException = $true
        }
        $sourceServer = Connect-DbaInstance @splatAddSchedule
        $sqlAddSchedule = "EXEC msdb.dbo.sp_add_schedule @schedule_name = N'$scheduleName', @freq_type = 4, @freq_interval = 1, @active_start_time = 010000"
        $sourceServer.Query($sqlAddSchedule)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $scheduleName = "dbatoolsci_DailySchedule"

        # Remove schedule from source instance
        $splatRemoveSource = @{
            SqlInstance     = $TestConfig.instance2
            EnableException = $true
        }
        $sourceServer = Connect-DbaInstance @splatRemoveSource
        $sqlDeleteSource = "EXEC msdb.dbo.sp_delete_schedule @schedule_name = '$scheduleName'"
        $sourceServer.Query($sqlDeleteSource)

        # Remove schedule from destination instance
        $splatRemoveDest = @{
            SqlInstance     = $TestConfig.instance3
            EnableException = $true
        }
        $destServer = Connect-DbaInstance @splatRemoveDest
        $sqlDeleteDest = "EXEC msdb.dbo.sp_delete_schedule @schedule_name = '$scheduleName'"
        $destServer.Query($sqlDeleteDest)

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When copying agent schedule between instances" {
        BeforeAll {
            $splatCopySchedule = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
            }
            $copyResults = Copy-DbaAgentSchedule @splatCopySchedule
        }

        It "Returns more than one result" {
            $copyResults.Status.Count | Should -BeGreaterThan 1
        }

        It "Contains at least one successful copy" {
            $copyResults | Where-Object Status -eq "Successful" | Should -Not -BeNullOrEmpty
        }

        It "Creates schedule with correct start time" {
            $splatGetSchedule = @{
                SqlInstance = $TestConfig.instance3
                Schedule    = "dbatoolsci_DailySchedule"
            }
            $copiedSchedule = Get-DbaAgentSchedule @splatGetSchedule
            $copiedSchedule.ActiveStartTimeOfDay | Should -Be "01:00:00"
        }
    }
}
