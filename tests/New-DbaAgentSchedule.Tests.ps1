$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'Schedule', 'Disabled', 'FrequencyType', 'FrequencyInterval', 'FrequencySubdayType', 'FrequencySubdayInterval', 'FrequencyRelativeInterval', 'FrequencyRecurrenceFactor', 'StartDate', 'EndDate', 'StartTime', 'EndTime', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_newschedule' -OwnerLogin 'sa'
        $null = New-DbaAgentJobStep -SqlInstance $script:instance2 -Job 'dbatoolsci_newschedule' -StepId 1 -StepName 'dbatoolsci Test Select' -Subsystem TransactSql -SubsystemServer $script:instance2 -Command "SELECT * FROM master.sys.all_columns;" -CmdExecSuccessCode 0 -OnSuccessAction QuitWithSuccess -OnFailAction QuitWithFailure -Database master -DatabaseUser sa

        $start = (Get-Date).AddDays(2).ToString('yyyyMMdd')
        $end = (Get-Date).AddDays(4).ToString('yyyyMMdd')
    }
    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_newschedule'
    }

    Context "Should create schedules based on static frequency" {
        BeforeAll {
            $results = New-Object System.collections.arraylist
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object {$_.name -like 'dbatools*'} |
                Remove-DbaAgentSchedule -Confirm:$false -Force
            Remove-Variable -Name results
        }

        foreach ($frequency in ('Once', 'AgentStart', 'IdleComputer')) {
            $variables = @{SqlInstance    = $script:instance2
                Schedule                  = "dbatoolsci_$frequency"
                Job                       = 'dbatoolsci_newschedule'
                FrequencyType             = $frequency
                FrequencyRecurrenceFactor = '1'
            }

            if ($frequency -ne 'IdleComputer') {
                $results.add($(New-DbaAgentSchedule -StartDate $start -StartTime '010000' -EndDate $end -EndTime '020000' @variables))
            } else {
                $results.add($(New-DbaAgentSchedule -Disabled -Force @variables))
            }
        }

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "$($r.name) Should be a schedule on an existing job" {
                $($r.parent) | Should Be 'dbatoolsci_newschedule'
            }
        }
    }

    Context "Should create schedules based on calendar frequency" {
        BeforeAll {
            $results = New-Object System.collections.arraylist
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object {$_.name -like 'dbatools*'} |
                Remove-DbaAgentSchedule -Confirm:$false -Force
            Remove-Variable -Name results
        }

        foreach ($frequency in ('Daily', 'Weekly', 'Monthly', 'MonthlyRelative')) {
            $variables = @{SqlInstance    = $script:instance2
                Schedule                  = "dbatoolsci_$frequency"
                Job                       = 'dbatoolsci_newschedule'
                FrequencyType             = $frequency
                FrequencyRecurrenceFactor = '1'
                FrequencyInterval         = '1'
                FrequencyRelativeInterval = 'First'
                StartDate                 = $start
                StartTime                 = '010000'
                EndDate                   = $end
                EndTime                   = '020000'
            }

            $results.add( $(New-DbaAgentSchedule @variables))
        }

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "$($r.name) Should be a schedule on an existing job" {
                $($r.parent) | Should Be 'dbatoolsci_newschedule'
            }
        }
    }

    Context "Should create schedules with various frequency interval" {
        BeforeAll {
            $results = New-Object System.collections.arraylist
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object {$_.name -like 'dbatools*'} |
                Remove-DbaAgentSchedule -Confirm:$false -Force
            Remove-Variable -Name results
        }

        foreach ($frequencyinterval in ('EveryDay', 'Weekdays', 'Weekend', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
                1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31)) {
            $variables = @{SqlInstance    = $script:instance2
                Schedule                  = "dbatoolsci_$frequencyinterval"
                Job                       = 'dbatoolsci_newschedule'
                FrequencyType             = 'Daily'
                FrequencyRecurrenceFactor = '1'
                FrequencyInterval         = $frequencyinterval
                StartDate                 = $start
                StartTime                 = '010000'
                EndDate                   = $end
                EndTime                   = '020000'
            }

            $results.add( $(New-DbaAgentSchedule @variables))
        }

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "$($r.name) Should be a schedule on an existing job" {
                $($r.parent) | Should Be 'dbatoolsci_newschedule'
            }
        }
    }

    Context "Should create schedules with various frequency subday type" {
        BeforeAll {
            $results = New-Object System.collections.arraylist
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object {$_.name -like 'dbatools*'} |
                Remove-DbaAgentSchedule -Confirm:$false -Force
            Remove-Variable -Name results
        }

        foreach ($FrequencySubdayType in ('Time', 'Seconds', 'Minutes', 'Hours')) {
            $variables = @{SqlInstance    = $script:instance2
                Schedule                  = "dbatoolsci_$FrequencySubdayType"
                Job                       = 'dbatoolsci_newschedule'
                FrequencyRecurrenceFactor = '1'
                FrequencySubdayInterval   = '1'
                FrequencySubdayType       = $FrequencySubdayType
                StartDate                 = $start
                StartTime                 = '010000'
                EndDate                   = $end
                EndTime                   = '020000'
            }

            $results.add( $(New-DbaAgentSchedule @variables))
        }

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "$($r.name) Should be a schedule on an existing job" {
                $($r.parent) | Should Be 'dbatoolsci_newschedule'
            }
        }
    }

    Context "Should create schedules with various frequency relative interval" {
        BeforeAll {
            $results = New-Object System.collections.arraylist
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object {$_.name -like 'dbatools*'} |
                Remove-DbaAgentSchedule -Confirm:$false -Force
            Remove-Variable -Name results
        }

        foreach ($FrequencyRelativeInterval in ('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')) {
            $variables = @{SqlInstance    = $script:instance2
                Schedule                  = "dbatoolsci_$FrequencyRelativeInterval"
                Job                       = 'dbatoolsci_newschedule'
                FrequencyRecurrenceFactor = '1'
                FrequencyRelativeInterval = $FrequencyRelativeInterval
                StartDate                 = $start
                StartTime                 = '010000'
                EndDate                   = $end
                EndTime                   = '020000'
            }

            $results.add( $(New-DbaAgentSchedule @variables))
        }

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "$($r.name) Should be a schedule on an existing job" {
                $($r.parent) | Should Be 'dbatoolsci_newschedule'
            }
        }
    }
}