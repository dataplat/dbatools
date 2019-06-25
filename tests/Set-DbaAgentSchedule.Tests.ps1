$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Job', 'ScheduleName', 'NewName', 'Enabled', 'Disabled', 'FrequencyType', 'FrequencyInterval', 'FrequencySubdayType', 'FrequencySubdayInterval', 'FrequencyRelativeInterval', 'FrequencyRecurrenceFactor', 'StartDate', 'EndDate', 'StartTime', 'EndTime', 'EnableException', 'Force'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_setschedule1' -OwnerLogin 'sa'
        $null = New-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_setschedule2' -OwnerLogin 'sa'
        $start = (Get-Date).AddDays(2).ToString('yyyyMMdd')
        $end = (Get-Date).AddDays(4).ToString('yyyyMMdd')
        $altstart = (Get-Date).AddDays(3).ToString('yyyyMMdd')
        $altend = (Get-Date).AddDays(5).ToString('yyyyMMdd')
    }
    AfterAll {
        $null = Remove-DbaAgentJob -SqlInstance $script:instance2 -Job 'dbatoolsci_setschedule1', 'dbatoolsci_setschedule2'
    }
    Context "Should rename schedule" {
        BeforeAll {
            $variables = @{SqlInstance    = $script:instance2
                Schedule                  = 'dbatoolsci_oldname'
                Job                       = 'dbatoolsci_setschedule1'
                FrequencyRecurrenceFactor = '1'
                FrequencySubdayInterval   = '5'
                FrequencySubdayType       = 'Time'
                StartDate                 = $start
                StartTime                 = '010000'
                EndDate                   = $end
                EndTime                   = '020000'
            }

            $null = New-DbaAgentSchedule @variables
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object {$_.name -like 'dbatools*'} |
                Remove-DbaAgentSchedule -Confirm:$false -Force
        }
        $schedules = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object {$_.name -like 'dbatools*'}
        $variables = @{SqlInstance    = $script:instance2
            Schedule                  = "dbatoolsci_oldname"
            NewName                   = "dbatoolsci_newname"
            Job                       = 'dbatoolsci_setschedule1'
            FrequencyRecurrenceFactor = '6'
            FrequencySubdayInterval   = '4'
            StartDate                 = $altstart
            StartTime                 = '113300'
            EndDate                   = $altend
            EndTime                   = '221100'
        }

        $null = Set-DbaAgentSchedule @variables
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object {$_.name -like 'dbatools*'}

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "$($r.name) Should have different name" {
                $($r.name) | Should Not Be "$($schedules.where({$_.id -eq $r.id}).name)"
            }
        }
    }

    Context "Should set schedules based on static frequency" {
        BeforeAll {
            foreach ($frequency in ('Once', 'AgentStart', 'IdleComputer')) {
                $variables = @{SqlInstance    = $script:instance2
                    Schedule                  = "dbatoolsci_$frequency"
                    Job                       = 'dbatoolsci_setschedule1'
                    FrequencyType             = $frequency
                    FrequencyRecurrenceFactor = '1'
                }

                if ($frequency -ne 'IdleComputer') {
                    $null = New-DbaAgentSchedule -StartDate $start -StartTime '010000' -EndDate $end -EndTime '020000' @variables
                } else {
                    $null = New-DbaAgentSchedule -Disabled -Force @variables
                }
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object {$_.name -like 'dbatools*'} |
                Remove-DbaAgentSchedule -Confirm:$false -Force
        }

        $schedules = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object {$_.name -like 'dbatools*'}
        foreach ($schedule in $schedules) {
            foreach ($frequency in ('Once', '1' , 'AgentStart', '64', 'IdleComputer', '128')) {
                $variables = @{SqlInstance    = $script:instance2
                    Schedule                  = "$($schedule.name)"
                    Job                       = 'dbatoolsci_setschedule1'
                    FrequencyType             = $frequency
                    FrequencyRecurrenceFactor = '5'
                }

                if ($frequency -notin ('IdleComputer', '128')) {
                    $null = Set-DbaAgentSchedule -StartDate $altstart -StartTime '113300' -EndDate $altend -EndTime '221100' -Disabled @variables
                } else {
                    $null = Set-DbaAgentSchedule -Enabled -Force @variables
                }
            }
        }
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object {$_.name -like 'dbatools*'}

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "$($r.name) Should have a frequency of OnIdle" {
                $($r.FrequencyTypes) | Should Be 'OnIdle'
            }
            It "$($r.name) Should be Enabled" {
                $($r.isEnabled) | Should Be 'True'
            }
        }
    }

    Context "Should set schedules based on calendar frequency" {
        BeforeAll {
            foreach ($frequency in ('Daily', 'Weekly', 'Monthly', 'MonthlyRelative')) {
                $variables = @{SqlInstance    = $script:instance2
                    Schedule                  = "dbatoolsci_$frequency"
                    Job                       = 'dbatoolsci_setschedule2'
                    FrequencyType             = $frequency
                    FrequencyRecurrenceFactor = '1'
                    FrequencyInterval         = '1'
                    FrequencyRelativeInterval = 'First'
                    StartDate                 = $start
                    StartTime                 = '010000'
                    EndDate                   = $end
                    EndTime                   = '020000'
                }

                $null = New-DbaAgentSchedule @variables
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object {$_.name -like 'dbatools*'} |
                Remove-DbaAgentSchedule -Confirm:$false -Force
        }

        $schedules = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object {$_.name -like 'dbatools*'}
        foreach ($schedule in $schedules) {
            foreach ($frequency in ('Daily', '4', 'Weekly', '8', 'Monthly', '16', 'MonthlyRelative', '32')) {
                $variables = @{SqlInstance    = $script:instance2
                    Schedule                  = "$($schedule.name)"
                    Job                       = 'dbatoolsci_setschedule2'
                    FrequencyType             = $frequency
                    FrequencyRecurrenceFactor = '6'
                    FrequencyInterval         = '4'
                    FrequencyRelativeInterval = 'Second'
                    StartDate                 = $altstart
                    StartTime                 = '113300'
                    EndDate                   = $altend
                    EndTime                   = '221100'
                }

                $null = Set-DbaAgentSchedule @variables
            }
        }
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object {$_.name -like 'dbatools*'}

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "$($r.name) Should have a frequency of MonthlyRelative" {
                $($r.FrequencyTypes) | Should Be 'MonthlyRelative'
            }
            It "$($r.name) Should have different StartTime" {
                $($r.StartTime) | Should Not Be "$($schedules.where({$_.id -eq $r.id}).StartTime)"
            }
        }
    }

    Context "Should set schedules with various frequency subday type" {
        BeforeAll {
            foreach ($FrequencySubdayType in ('Time', 'Seconds', 'Minutes', 'Hours')) {
                $variables = @{SqlInstance    = $script:instance2
                    Schedule                  = "dbatoolsci_$FrequencySubdayType"
                    Job                       = 'dbatoolsci_setschedule1'
                    FrequencyRecurrenceFactor = '1'
                    FrequencySubdayInterval   = '5'
                    FrequencySubdayType       = $FrequencySubdayType
                    StartDate                 = $start
                    StartTime                 = '010000'
                    EndDate                   = $end
                    EndTime                   = '020000'
                }

                $null = New-DbaAgentSchedule @variables
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object {$_.name -like 'dbatools*'} |
                Remove-DbaAgentSchedule -Confirm:$false -Force
        }
        $schedules = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object {$_.name -like 'dbatools*'}
        foreach ($schedule in $schedules) {
            foreach ($FrequencySubdayType in ('Time', '1', 'Seconds', '2', 'Minutes', '4', 'Hours', '8')) {
                $variables = @{SqlInstance    = $script:instance2
                    Schedule                  = "$schedule"
                    Job                       = 'dbatoolsci_setschedule1'
                    FrequencyRecurrenceFactor = '6'
                    FrequencySubdayInterval   = '4'
                    FrequencySubdayType       = $FrequencySubdayType
                    StartDate                 = $altstart
                    StartTime                 = '113300'
                    EndDate                   = $altend
                    EndTime                   = '221100'
                }

                $null = Set-DbaAgentSchedule @variables
            }
        }
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object {$_.name -like 'dbatools*'}

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "$($r.name) Should have different EndDate" {
                $($r.EndDate) | Should Not Be "$($schedules.where({$_.id -eq $r.id}).EndDate)"
            }
        }
    }

    Context "Should set schedules with various frequency relative interval" {
        BeforeAll {
            foreach ($FrequencyRelativeInterval in ('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')) {
                $variables = @{SqlInstance    = $script:instance2
                    Schedule                  = "dbatoolsci_$FrequencyRelativeInterval"
                    Job                       = 'dbatoolsci_setschedule2'
                    FrequencyRecurrenceFactor = '1'
                    FrequencyRelativeInterval = $FrequencyRelativeInterval
                    StartDate                 = $start
                    StartTime                 = '010000'
                    EndDate                   = $end
                    EndTime                   = '020000'
                }

                $null = New-DbaAgentSchedule @variables
            }
        }
        AfterAll {
            $null = Get-DbaAgentSchedule -SqlInstance $script:instance2 |
                Where-Object {$_.name -like 'dbatools*'} |
                Remove-DbaAgentSchedule -Confirm:$false -Force
        }
        $schedules = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object {$_.name -like 'dbatools*'}
        foreach ($schedule in $schedules) {
            foreach ($FrequencyRelativeInterval in ('Unused', 'First', 'Second', 'Third', 'Fourth', 'Last')) {
                $variables = @{SqlInstance    = $script:instance2
                    Schedule                  = "$schedule"
                    Job                       = 'dbatoolsci_setschedule2'
                    FrequencyRecurrenceFactor = '4'
                    FrequencyRelativeInterval = $FrequencyRelativeInterval
                    StartDate                 = $altstart
                    StartTime                 = '113300'
                    EndDate                   = $altend
                    EndTime                   = '221100'
                }

                $null = Set-DbaAgentSchedule @variables
            }
        }
        $results = Get-DbaAgentSchedule -SqlInstance $script:instance2 | Where-Object {$_.name -like 'dbatools*'}

        It "Should have Results" {
            $results | Should Not BeNullOrEmpty
        }
        foreach ($r in $results) {
            It "$($r.name) Should have different EndTime" {
                $($r.EndTime) | Should Not Be "$($schedules.where({$_.id -eq $r.id}).EndTime)"
            }
        }
    }
}