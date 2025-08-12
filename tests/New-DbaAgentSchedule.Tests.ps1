#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentSchedule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Job",
                "Schedule",
                "Disabled",
                "FrequencyType",
                "FrequencyInterval",
                "FrequencySubdayType",
                "FrequencySubdayInterval",
                "FrequencyRelativeInterval",
                "FrequencyRecurrenceFactor",
                "StartDate",
                "EndDate",
                "StartTime",
                "EndTime",
                "Owner",
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

        $splatJob = @{
            SqlInstance     = $TestConfig.instance2
            Job             = "dbatoolsci_newschedule"
            OwnerLogin      = "sa"
            EnableException = $true
        }
        $null = New-DbaAgentJob @splatJob

        $splatJobStep = @{
            SqlInstance        = $TestConfig.instance2
            Job                = "dbatoolsci_newschedule"
            StepId             = 1
            StepName           = "dbatoolsci Test Select"
            Subsystem          = "TransactSql"
            SubsystemServer    = $TestConfig.instance2
            Command            = "SELECT * FROM master.sys.all_columns;"
            CmdExecSuccessCode = 0
            OnSuccessAction    = "QuitWithSuccess"
            OnFailAction       = "QuitWithFailure"
            Database           = "master"
            DatabaseUser       = "dbo"
            EnableException    = $true
        }
        $null = New-DbaAgentJobStep @splatJobStep

        $global:start = (Get-Date).AddDays(2).ToString("yyyyMMdd")
        $global:end = (Get-Date).AddDays(4).ToString("yyyyMMdd")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job "dbatoolsci_newschedule" -Confirm:$false
    }

    Context "Should create schedules based on frequency type" {
        BeforeAll {
            $global:frequencyResults = @{ }

            $scheduleOptions = @("Once", "OneTime", "Daily", "Weekly", "Monthly", "MonthlyRelative", "AgentStart", "AutoStart", "IdleComputer", "OnIdle")

            foreach ($frequency in $scheduleOptions) {
                $splatSchedule = @{
                    SqlInstance               = $TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequency"
                    Job                       = "dbatoolsci_newschedule"
                    FrequencyType             = $frequency
                    FrequencyRecurrenceFactor = "1"
                    FrequencyInterval         = "1"
                    FrequencyRelativeInterval = "First"
                }

                if ($frequency -notin @("IdleComputer", "OnIdle")) {
                    $global:frequencyResults[$frequency] = New-DbaAgentSchedule -StartDate $global:start -StartTime "010000" -EndDate $global:end -EndTime "020000" @splatSchedule
                } else {
                    $global:frequencyResults[$frequency] = New-DbaAgentSchedule -Disabled -Force @splatSchedule
                }
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.instance2 |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Confirm:$false -Force -ErrorAction SilentlyContinue
        }

        It "Should have Results" {
            $global:frequencyResults | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have the correct frequency type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job "dbatoolsci_newschedule").JobID
            foreach ($key in $global:frequencyResults.keys) {
                $global:frequencyResults[$key].EnumJobReferences() | Should -Contain $jobId
                $global:frequencyResults[$key].FrequencyTypes | Should -BeIn $scheduleOptions
                $global:frequencyResults[$key].JobCount | Should -Be 1

                if ($key -in @("IdleComputer", "OnIdle")) {
                    $global:frequencyResults[$key].FrequencyTypes | Should -Be "OnIdle"
                } elseif ($key -in @("Once", "OneTime")) {
                    $global:frequencyResults[$key].FrequencyTypes | Should -Be "OneTime"
                } elseif ($key -in @("AgentStart", "AutoStart")) {
                    $global:frequencyResults[$key].FrequencyTypes | Should -Be "AutoStart"
                } else {
                    $global:frequencyResults[$key].FrequencyTypes | Should -Be $key
                }
            }
        }
    }

    Context "Should create schedules with various frequency interval" {
        BeforeAll {
            $global:intervalResults = @{ }

            foreach ($frequencyinterval in ("EveryDay", "Weekdays", "Weekend", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
                    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31)) {

                if ($frequencyinterval -is [int]) {
                    $frequencyType = "Monthly"
                } else {
                    $frequencyType = "Weekly"
                }

                $splatScheduleInterval = @{
                    SqlInstance               = $TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequencyinterval"
                    Job                       = "dbatoolsci_newschedule"
                    FrequencyType             = $frequencyType
                    FrequencyRecurrenceFactor = "1"
                    FrequencyInterval         = $frequencyinterval
                    StartDate                 = $global:start
                    StartTime                 = "010000"
                    EndDate                   = $global:end
                    EndTime                   = "020000"
                }

                $global:intervalResults[$frequencyinterval] = New-DbaAgentSchedule @splatScheduleInterval
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.instance2 |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Confirm:$false -Force -ErrorAction SilentlyContinue
        }

        It "Should have Results" {
            $global:intervalResults | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have the correct interval for the frequency type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job "dbatoolsci_newschedule").JobID
            foreach ($key in $global:intervalResults.keys) {
                $global:intervalResults[$key].EnumJobReferences() | Should -Contain $jobId

                if ($global:intervalResults[$key].FrequencyTypes -eq "Monthly") {
                    $global:intervalResults[$key].FrequencyInterval | Should -Be $key
                } elseif ($global:intervalResults[$key].FrequencyTypes -eq "Weekly") {
                    switch ($key) {
                        "Sunday" { $global:intervalResults[$key].FrequencyInterval | Should -Be 1 }
                        "Monday" { $global:intervalResults[$key].FrequencyInterval | Should -Be 2 }
                        "Tuesday" { $global:intervalResults[$key].FrequencyInterval | Should -Be 4 }
                        "Wednesday" { $global:intervalResults[$key].FrequencyInterval | Should -Be 8 }
                        "Thursday" { $global:intervalResults[$key].FrequencyInterval | Should -Be 16 }
                        "Friday" { $global:intervalResults[$key].FrequencyInterval | Should -Be 32 }
                        "Saturday" { $global:intervalResults[$key].FrequencyInterval | Should -Be 64 }
                        "Weekdays" { $global:intervalResults[$key].FrequencyInterval | Should -Be 62 }
                        "Weekend" { $global:intervalResults[$key].FrequencyInterval | Should -Be 65 }
                        "EveryDay" { $global:intervalResults[$key].FrequencyInterval | Should -Be 127 }
                    }
                }
            }
        }
    }

    Context "Should create schedules with various frequency subday type" {
        BeforeAll {
            $global:subdayResults = @{ }

            $scheduleOptions = @("Time", "Once", "Second", "Seconds", "Minute", "Minutes", "Hour", "Hours")

            foreach ($frequencySubdayType in $scheduleOptions) {
                $splatScheduleSubday = @{
                    SqlInstance               = $TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequencySubdayType"
                    Job                       = "dbatoolsci_newschedule"
                    FrequencyType             = "Daily"
                    FrequencyInterval         = "1"
                    FrequencyRecurrenceFactor = "1"
                    FrequencySubdayInterval   = 10
                    FrequencySubdayType       = $frequencySubdayType
                    StartDate                 = $global:start
                    StartTime                 = "010000"
                    EndDate                   = $global:end
                    EndTime                   = "020000"
                }

                $global:subdayResults[$frequencySubdayType] = New-DbaAgentSchedule @splatScheduleSubday
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.instance2 |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Confirm:$false -Force -ErrorAction SilentlyContinue
        }

        It "Should have Results" {
            $global:subdayResults | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have a valid frequency subday type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job "dbatoolsci_newschedule").JobID
            foreach ($key in $global:subdayResults.keys) {
                $global:subdayResults[$key].EnumJobReferences() | Should -Contain $jobId
                $global:subdayResults[$key].FrequencySubdayTypes | Should -BeIn $scheduleOptions

                if ($key -in @("Second", "Seconds")) {
                    $global:subdayResults[$key].FrequencySubdayTypes | Should -Be "Second"
                } elseif ($key -in @("Minute", "Minutes")) {
                    $global:subdayResults[$key].FrequencySubdayTypes | Should -Be "Minute"
                } elseif ($key -in @("Hour", "Hours")) {
                    $global:subdayResults[$key].FrequencySubdayTypes | Should -Be "Hour"
                } elseif ($key -in @("Once", "Time")) {
                    $global:subdayResults[$key].FrequencySubdayTypes | Should -Be "Once"
                } else {
                    $global:subdayResults[$key].FrequencySubdayTypes | Should -Be $key
                }
            }
        }
    }

    Context "Should create schedules with various frequency relative interval" {
        BeforeAll {
            $global:relativeResults = @{ }

            # Unused (value of 0) is not valid for sp_add_jobschedule when using the MonthlyRelative frequency type, so 'Unused' has been removed from this test.
            $scheduleOptions = @("First", "Second", "Third", "Fourth", "Last")

            foreach ($frequencyRelativeInterval in $scheduleOptions) {
                $splatScheduleRelative = @{
                    SqlInstance               = $TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequencyRelativeInterval"
                    Job                       = "dbatoolsci_newschedule"
                    FrequencyType             = "MonthlyRelative"           # required to set the FrequencyRelativeInterval
                    FrequencyRecurrenceFactor = "2"                         # every 2 months
                    FrequencyRelativeInterval = $frequencyRelativeInterval  # 'First', 'Second', 'Third', 'Fourth', 'Last'
                    FrequencyInterval         = "6"                         # Friday or day 6
                    FrequencySubDayInterval   = "1"                         # daily frequency 1="occurs once at..." or "occurs every..."
                    FrequencySubDayType       = "Once"
                    StartDate                 = $global:start
                    StartTime                 = "010000"
                    EndDate                   = $global:end
                    EndTime                   = "020000"
                }

                $global:relativeResults[$frequencyRelativeInterval] = New-DbaAgentSchedule @splatScheduleRelative
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $TestConfig.instance2 |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Confirm:$false -Force -ErrorAction SilentlyContinue
        }

        It "Should have Results" {
            $global:relativeResults | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have a valid frequency relative interval" {
            $jobId = (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job "dbatoolsci_newschedule").JobID
            foreach ($key in $global:relativeResults.keys) {
                $global:relativeResults[$key].EnumJobReferences() | Should -Contain $jobId
                $global:relativeResults[$key].FrequencyRelativeIntervals | Should -BeIn $scheduleOptions
                $global:relativeResults[$key].FrequencyRelativeIntervals | Should -Be $key
            }
        }
    }
}