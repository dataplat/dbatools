#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = New-DbaAgentJob -SqlInstance $global:TestConfig.instance2 -Job "dbatoolsci_newschedule" -OwnerLogin "sa"
        $null = New-DbaAgentJobStep -SqlInstance $global:TestConfig.instance2 -Job "dbatoolsci_newschedule" -StepId 1 -StepName "dbatoolsci Test Select" -Subsystem TransactSql -SubsystemServer $global:TestConfig.instance2 -Command "SELECT * FROM master.sys.all_columns;" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -DatabaseUser dbo

        $script:start = (Get-Date).AddDays(2).ToString("yyyyMMdd")
        $script:end = (Get-Date).AddDays(4).ToString("yyyyMMdd")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAgentJob -SqlInstance $global:TestConfig.instance2 -Job "dbatoolsci_newschedule" -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "Should create schedules based on frequency type" {
        BeforeAll {
            $script:results = @{ }

            $scheduleOptions = @("Once", "OneTime", "Daily", "Weekly", "Monthly", "MonthlyRelative", "AgentStart", "AutoStart", "IdleComputer", "OnIdle")

            foreach ($frequency in $scheduleOptions) {
                $splatSchedule = @{
                    SqlInstance               = $global:TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequency"
                    Job                       = "dbatoolsci_newschedule"
                    FrequencyType             = $frequency
                    FrequencyRecurrenceFactor = "1"
                    FrequencyInterval         = "1"
                    FrequencyRelativeInterval = "First"
                }

                if ($frequency -notin @("IdleComputer", "OnIdle")) {
                    $script:results[$frequency] = New-DbaAgentSchedule -StartDate $script:start -StartTime "010000" -EndDate $script:end -EndTime "020000" @splatSchedule
                } else {
                    $script:results[$frequency] = New-DbaAgentSchedule -Disabled -Force @splatSchedule
                }
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $global:TestConfig.instance2 |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Confirm:$false -Force -ErrorAction SilentlyContinue
        }

        It "Should have Results" {
            @($script:results) | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have the correct frequency type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $global:TestConfig.instance2 -Job "dbatoolsci_newschedule").JobID
            foreach ($key in $script:results.keys) {
                $script:results[$key].EnumJobReferences() | Should -Contain $jobId
                $script:results[$key].FrequencyTypes | Should -BeIn $scheduleOptions
                $script:results[$key].JobCount | Should -Be 1

                if ($key -in @("IdleComputer", "OnIdle")) {
                    $script:results[$key].FrequencyTypes | Should -Be "OnIdle"
                } elseif ($key -in @("Once", "OneTime")) {
                    $script:results[$key].FrequencyTypes | Should -Be "OneTime"
                } elseif ($key -in @("AgentStart", "AutoStart")) {
                    $script:results[$key].FrequencyTypes | Should -Be "AutoStart"
                } else {
                    $script:results[$key].FrequencyTypes | Should -Be $key
                }
            }
        }
    }

    Context "Should create schedules with various frequency interval" {
        BeforeAll {
            $script:results = @{ }

            foreach ($frequencyinterval in ("EveryDay", "Weekdays", "Weekend", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
                    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31)) {

                if ($frequencyinterval -is [int]) {
                    $frequencyType = "Monthly"
                } else {
                    $frequencyType = "Weekly"
                }

                $splatScheduleInterval = @{
                    SqlInstance               = $global:TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequencyinterval"
                    Job                       = "dbatoolsci_newschedule"
                    FrequencyType             = $frequencyType
                    FrequencyRecurrenceFactor = "1"
                    FrequencyInterval         = $frequencyinterval
                    StartDate                 = $script:start
                    StartTime                 = "010000"
                    EndDate                   = $script:end
                    EndTime                   = "020000"
                }

                $script:results[$frequencyinterval] = New-DbaAgentSchedule @splatScheduleInterval
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $global:TestConfig.instance2 |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Confirm:$false -Force -ErrorAction SilentlyContinue
        }

        It "Should have Results" {
            @($script:results) | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have the correct interval for the frequency type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $global:TestConfig.instance2 -Job "dbatoolsci_newschedule").JobID
            foreach ($key in $script:results.keys) {
                $script:results[$key].EnumJobReferences() | Should -Contain $jobId

                if ($script:results[$key].FrequencyTypes -eq "Monthly") {
                    $script:results[$key].FrequencyInterval | Should -Be $key
                } elseif ($script:results[$key].FrequencyTypes -eq "Weekly") {
                    switch ($key) {
                        "Sunday" { $script:results[$key].FrequencyInterval | Should -Be 1 }
                        "Monday" { $script:results[$key].FrequencyInterval | Should -Be 2 }
                        "Tuesday" { $script:results[$key].FrequencyInterval | Should -Be 4 }
                        "Wednesday" { $script:results[$key].FrequencyInterval | Should -Be 8 }
                        "Thursday" { $script:results[$key].FrequencyInterval | Should -Be 16 }
                        "Friday" { $script:results[$key].FrequencyInterval | Should -Be 32 }
                        "Saturday" { $script:results[$key].FrequencyInterval | Should -Be 64 }
                        "Weekdays" { $script:results[$key].FrequencyInterval | Should -Be 62 }
                        "Weekend" { $script:results[$key].FrequencyInterval | Should -Be 65 }
                        "EveryDay" { $script:results[$key].FrequencyInterval | Should -Be 127 }
                    }
                }
            }
        }
    }

    Context "Should create schedules with various frequency subday type" {
        BeforeAll {
            $script:results = @{ }

            $scheduleOptions = @("Time", "Once", "Second", "Seconds", "Minute", "Minutes", "Hour", "Hours")

            foreach ($frequencySubdayType in $scheduleOptions) {
                $splatScheduleSubday = @{
                    SqlInstance               = $global:TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequencySubdayType"
                    Job                       = "dbatoolsci_newschedule"
                    FrequencyType             = "Daily"
                    FrequencyInterval         = "1"
                    FrequencyRecurrenceFactor = "1"
                    FrequencySubdayInterval   = 10
                    FrequencySubdayType       = $frequencySubdayType
                    StartDate                 = $script:start
                    StartTime                 = "010000"
                    EndDate                   = $script:end
                    EndTime                   = "020000"
                }

                $script:results[$frequencySubdayType] = New-DbaAgentSchedule @splatScheduleSubday
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $global:TestConfig.instance2 |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Confirm:$false -Force -ErrorAction SilentlyContinue
        }

        It "Should have Results" {
            @($script:results) | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have a valid frequency subday type" {
            $jobId = (Get-DbaAgentJob -SqlInstance $global:TestConfig.instance2 -Job "dbatoolsci_newschedule").JobID
            foreach ($key in $script:results.keys) {
                $script:results[$key].EnumJobReferences() | Should -Contain $jobId
                $script:results[$key].FrequencySubdayTypes | Should -BeIn $scheduleOptions

                if ($key -in @("Second", "Seconds")) {
                    $script:results[$key].FrequencySubdayTypes | Should -Be "Second"
                } elseif ($key -in @("Minute", "Minutes")) {
                    $script:results[$key].FrequencySubdayTypes | Should -Be "Minute"
                } elseif ($key -in @("Hour", "Hours")) {
                    $script:results[$key].FrequencySubdayTypes | Should -Be "Hour"
                } elseif ($key -in @("Once", "Time")) {
                    $script:results[$key].FrequencySubdayTypes | Should -Be "Once"
                } else {
                    $script:results[$key].FrequencySubdayTypes | Should -Be $key
                }
            }
        }
    }

    Context "Should create schedules with various frequency relative interval" {
        BeforeAll {
            $script:results = @{ }

            # Unused (value of 0) is not valid for sp_add_jobschedule when using the MonthlyRelative frequency type, so "Unused" has been removed from this test.
            $scheduleOptions = @("First", "Second", "Third", "Fourth", "Last")

            foreach ($frequencyRelativeInterval in $scheduleOptions) {
                $splatScheduleRelative = @{
                    SqlInstance               = $global:TestConfig.instance2
                    Schedule                  = "dbatoolsci_$frequencyRelativeInterval"
                    Job                       = "dbatoolsci_newschedule"
                    FrequencyType             = "MonthlyRelative"           # required to set the FrequencyRelativeInterval
                    FrequencyRecurrenceFactor = "2"                         # every 2 months
                    FrequencyRelativeInterval = $frequencyRelativeInterval  # "First", "Second", "Third", "Fourth", "Last"
                    FrequencyInterval         = "6"                         # Friday or day 6
                    FrequencySubDayInterval   = "1"                         # daily frequency 1="occurs once at..." or "occurs every..."
                    FrequencySubDayType       = "Once"
                    StartDate                 = $script:start
                    StartTime                 = "010000"
                    EndDate                   = $script:end
                    EndTime                   = "020000"
                }

                $script:results[$frequencyRelativeInterval] = New-DbaAgentSchedule @splatScheduleRelative
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $global:TestConfig.instance2 |
                Where-Object Name -like "dbatools*" |
                Remove-DbaAgentSchedule -Confirm:$false -Force -ErrorAction SilentlyContinue
        }

        It "Should have Results" {
            @($script:results) | Should -Not -BeNullOrEmpty
        }

        It "Should be a schedule on an existing job and have a valid frequency relative interval" {
            $jobId = (Get-DbaAgentJob -SqlInstance $global:TestConfig.instance2 -Job "dbatoolsci_newschedule").JobID
            foreach ($key in $script:results.keys) {
                $script:results[$key].EnumJobReferences() | Should -Contain $jobId
                $script:results[$key].FrequencyRelativeIntervals | Should -BeIn $scheduleOptions
                $script:results[$key].FrequencyRelativeIntervals | Should -Be $key
            }
        }
    }
}