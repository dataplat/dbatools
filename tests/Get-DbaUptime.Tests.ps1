#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaUptime",
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
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Should have correct properties" {
            $results = Get-DbaUptime -SqlInstance $TestConfig.InstanceMulti1
            $ExpectedProps = "ComputerName", "InstanceName", "SqlServer", "SqlUptime", "WindowsUptime", "SqlStartTime", "WindowsBootTime", "SinceSqlStart", "SinceWindowsBoot"
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }

    Context "Command can handle multiple SqlInstances" {
        BeforeAll {
            $results = Get-DbaUptime -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
        }

        It "Command resultset could contain 2 results" {
            $results.Count | Should -Be 2
        }

        It "Windows up time should be more than SQL Uptime for $($result.SqlServer)" {
            foreach ($result in $results) {
                $result.SqlUptime | Should -BeLessThan $result.WindowsUpTime
            }
        }
    }

    Context "Properties should return expected types" {
        BeforeAll {
            $results = Get-DbaUptime -SqlInstance $TestConfig.InstanceMulti1
        }

        It "SqlStartTime should be a DbaDateTime for $($result.SqlServer)" {
            foreach ($result in $results) {
                $result.SqlStartTime | Should -BeOfType DbaDateTime
            }
        }

        It "WindowsBootTime should be a DbaDateTime for $($result.SqlServer)" {
            foreach ($result in $results) {
                $result.WindowsBootTime | Should -BeOfType DbaDateTime
            }
        }
    }

    Context "When the clock of this computer is ahead of the instance" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A login without VIEW SERVER STATE cannot read sys.dm_os_sys_info
            $uptimeLoginName = "dbatoolsci_uptime_$(Get-Random)"
            $uptimePassword = ConvertTo-SecureString -String "dbatools.IO!$(Get-Random)" -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $uptimeLoginName -SecurePassword $uptimePassword
            $uptimeCredential = New-Object System.Management.Automation.PSCredential($uptimeLoginName, $uptimePassword)

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # Issue #10833: the instance records the creation of tempdb in its own local time. A test computer shares the
            # clock of its instance, so only the clock of this computer is moved ahead, the instance stays real.
            # An uptime counted up to this clock would be five hours too long.
            Mock -ModuleName dbatools -CommandName Get-Date -ParameterFilter { $PesterBoundParameters.Count -eq 0 } -MockWith { [datetime]::Now.AddHours(5) }
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $uptimeLoginName -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Lets the instance measure its uptime" {
            $result = Get-DbaUptime -SqlInstance $TestConfig.InstanceMulti1
            $expectedMilliseconds = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query "SELECT ms_ticks - sqlserver_start_time_ms_ticks AS UptimeMilliseconds FROM sys.dm_os_sys_info" -As SingleValue
            $WarnVar | Should -BeNullOrEmpty
            @($result).Count | Should -Be 1
            [math]::Abs($result.SqlUptime.TotalMilliseconds - $expectedMilliseconds) | Should -BeLessThan 120000
        }

        It "Has a login that cannot read sys.dm_os_sys_info" {
            # Without this the next test would pass on the path of a login with VIEW SERVER STATE and prove nothing
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -SqlCredential $uptimeCredential -Query "SELECT ms_ticks FROM sys.dm_os_sys_info" -WarningAction SilentlyContinue
            $WarnVar | Should -BeLike "*permission*denied*"
        }

        It "Counts the uptime up to the clock of the instance for a login without VIEW SERVER STATE" {
            $result = Get-DbaUptime -SqlInstance $TestConfig.InstanceMulti1 -SqlCredential $uptimeCredential
            # The instance measures the expected uptime itself, which neither a clock nor a time zone can shift. Its count starts
            # with the process, a few seconds before tempdb is created.
            $expectedMilliseconds = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query "SELECT ms_ticks - sqlserver_start_time_ms_ticks AS UptimeMilliseconds FROM sys.dm_os_sys_info" -As SingleValue
            $WarnVar | Should -BeNullOrEmpty
            @($result).Count | Should -Be 1
            [math]::Abs($result.SqlUptime.TotalMilliseconds - $expectedMilliseconds) | Should -BeLessThan 120000
        }
    }

    Context "When daylight saving time changed since the instance started" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A login without VIEW SERVER STATE, so that the uptime is counted from the creation of tempdb
            $dstLoginName = "dbatoolsci_uptimedst_$(Get-Random)"
            $dstPassword = ConvertTo-SecureString -String "dbatools.IO!$(Get-Random)" -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $dstLoginName -SecurePassword $dstPassword
            $dstCredential = New-Object System.Management.Automation.PSCredential($dstLoginName, $dstPassword)

            # The review of #10852: both ends of that count are local times of the instance, and an instance that started before a
            # daylight saving change has run an hour longer or shorter than their difference. The start of the instance cannot be
            # moved, so the server objects of the login report another creation of tempdb: the last noon of the past year at which
            # the time zone had another offset than today. Everything else, the queries included, runs on the real instance. In a
            # time zone without daylight saving time, such as UTC on the runners, there is no change to count, and the tests then
            # check the uptime only.
            $getStartBeforeOffsetChange = {
                param ($TimeZone)
                $offsetNow = $TimeZone.GetUtcOffset([datetime]::UtcNow)
                $startTime = [datetime]::SpecifyKind([datetime]::Today.AddDays(-2).AddHours(12), [System.DateTimeKind]::Unspecified)
                foreach ($daysBack in 2..366) {
                    $candidate = [datetime]::SpecifyKind([datetime]::Today.AddDays(-$daysBack).AddHours(12), [System.DateTimeKind]::Unspecified)
                    if ($TimeZone.GetUtcOffset($candidate) -ne $offsetNow) {
                        $startTime = $candidate
                        break
                    }
                }
                $startTime
            }

            $dstAdminServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $instanceNamesTimeZone = $dstAdminServer.VersionMajor -ge 16
            if ($instanceNamesTimeZone) {
                $instanceTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($dstAdminServer.Query("SELECT CURRENT_TIMEZONE_ID() AS TimeZoneId").TimeZoneId)
                $startInInstanceTimeZone = & $getStartBeforeOffsetChange $instanceTimeZone
                $serverInInstanceTimeZone = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -SqlCredential $dstCredential
                $tempdbInInstanceTimeZone = @{ tempdb = [PSCustomObject]@{ CreateDate = $startInInstanceTimeZone } }
                Add-Member -InputObject $serverInInstanceTimeZone -NotePropertyName Databases -NotePropertyValue $tempdbInInstanceTimeZone -Force
            }

            # Before SQL Server 2022 the instance cannot name its time zone, and the start is converted with the time zone of this
            # computer. This server object claims SQL Server 2019, so that the way is taken on every version.
            $startInLocalTimeZone = & $getStartBeforeOffsetChange ([System.TimeZoneInfo]::Local)
            $serverBefore2022 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -SqlCredential $dstCredential
            $tempdbInLocalTimeZone = @{ tempdb = [PSCustomObject]@{ CreateDate = $startInLocalTimeZone } }
            Add-Member -InputObject $serverBefore2022 -NotePropertyName Databases -NotePropertyValue $tempdbInLocalTimeZone -Force
            Add-Member -InputObject $serverBefore2022 -NotePropertyName Version -NotePropertyValue ([version]"15.0.4430.1") -Force

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($dstServer in $serverInInstanceTimeZone, $serverBefore2022, $dstAdminServer) {
                if ($dstServer) {
                    $null = $dstServer | Disconnect-DbaInstance
                }
            }
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $dstLoginName -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Counts a daylight saving change in the time zone of the instance" {
            if (-not $instanceNamesTimeZone) {
                Set-ItResult -Skipped -Because "the instance names its time zone with CURRENT_TIMEZONE_ID() from SQL Server 2022 on"
            }
            $logStart = Get-Date
            $result = Get-DbaUptime -SqlInstance $serverInInstanceTimeZone
            $getWarnings = $WarnVar
            $serverUtcTime = $dstAdminServer.Query("SELECT SYSUTCDATETIME() AS ServerUtcTime").ServerUtcTime
            $expectedUptime = $serverUtcTime - [System.TimeZoneInfo]::ConvertTimeToUtc($startInInstanceTimeZone, $instanceTimeZone)
            $getWarnings | Should -BeNullOrEmpty
            @($result).Count | Should -Be 1
            $result.SqlStartTime.ToString() | Should -Be ([dbadatetime]$startInInstanceTimeZone).ToString()
            [math]::Abs(($result.SqlUptime - $expectedUptime).TotalSeconds) | Should -BeLessThan 120
            # Proves the way: in the lab both time zones are the same, so the other way would give the same uptime
            $fallbackMessage = Get-DbatoolsLog -FunctionName Get-DbaUptime | Where-Object Timestamp -ge $logStart | Where-Object Message -like "Could not read sys.dm_os_sys_info*"
            $fallbackMessage.Message | Should -BeLike "*in its time zone*"
        }

        It "Counts a daylight saving change in the time zone of this computer before SQL Server 2022" {
            $logStart = Get-Date
            $result = Get-DbaUptime -SqlInstance $serverBefore2022
            $getWarnings = $WarnVar
            $serverUtcTime = $dstAdminServer.Query("SELECT SYSUTCDATETIME() AS ServerUtcTime").ServerUtcTime
            $expectedUptime = $serverUtcTime - [System.TimeZoneInfo]::ConvertTimeToUtc($startInLocalTimeZone, [System.TimeZoneInfo]::Local)
            $getWarnings | Should -BeNullOrEmpty
            @($result).Count | Should -Be 1
            $result.SqlStartTime.ToString() | Should -Be ([dbadatetime]$startInLocalTimeZone).ToString()
            [math]::Abs(($result.SqlUptime - $expectedUptime).TotalSeconds) | Should -BeLessThan 120
            $fallbackMessage = Get-DbatoolsLog -FunctionName Get-DbaUptime | Where-Object Timestamp -ge $logStart | Where-Object Message -like "Could not read sys.dm_os_sys_info*"
            $fallbackMessage.Message | Should -BeLike "*in the time zone of this computer*"
        }
    }

    Context "When the instance started in the hour that repeats when the clocks go back" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A login without VIEW SERVER STATE, so that the uptime is counted from the creation of tempdb
            $repeatLoginName = "dbatoolsci_uptimerepeat_$(Get-Random)"
            $repeatPassword = ConvertTo-SecureString -String "dbatools.IO!$(Get-Random)" -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $repeatLoginName -SecurePassword $repeatPassword
            $repeatCredential = New-Object System.Management.Automation.PSCredential($repeatLoginName, $repeatPassword)

            # The second review of #10852: the creation date of tempdb has no offset, and in the hour that repeats when the clocks
            # go back it names two times. AT TIME ZONE takes the first, so an instance that started in the second reported an hour
            # more. Such a start counts as the second occurrence, in standard time, as .NET converts it with ConvertTimeToUtc. The
            # server objects of the login report a creation of tempdb in the last quarter of an hour of the past year that repeated,
            # in quarters so that a change of half an hour is found too. In a time zone without such an hour, such as UTC on the
            # runners, the start is two days ago, and the tests then check the uptime only.
            $getStartInRepeatedHour = {
                param ($TimeZone)
                $startTime = [datetime]::SpecifyKind([datetime]::Today.AddDays(-2).AddHours(12), [System.DateTimeKind]::Unspecified)
                $candidate = [datetime]::SpecifyKind([datetime]::Today, [System.DateTimeKind]::Unspecified)
                $oldestCandidate = $candidate.AddDays(-366)
                while ($candidate -gt $oldestCandidate) {
                    if ($TimeZone.IsAmbiguousTime($candidate)) {
                        $startTime = $candidate
                        break
                    }
                    $candidate = $candidate.AddMinutes(-15)
                }
                $startTime
            }

            $repeatAdminServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $repeatInstanceNamesTimeZone = $repeatAdminServer.VersionMajor -ge 16
            if ($repeatInstanceNamesTimeZone) {
                $repeatInstanceTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($repeatAdminServer.Query("SELECT CURRENT_TIMEZONE_ID() AS TimeZoneId").TimeZoneId)
                $repeatStartInInstanceTimeZone = & $getStartInRepeatedHour $repeatInstanceTimeZone
                $repeatServerInInstanceTimeZone = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -SqlCredential $repeatCredential
                $repeatTempdbInInstanceTimeZone = @{ tempdb = [PSCustomObject]@{ CreateDate = $repeatStartInInstanceTimeZone } }
                Add-Member -InputObject $repeatServerInInstanceTimeZone -NotePropertyName Databases -NotePropertyValue $repeatTempdbInInstanceTimeZone -Force
            }

            # This server object claims SQL Server 2019, so that the start is converted with the time zone of this computer.
            $repeatStartInLocalTimeZone = & $getStartInRepeatedHour ([System.TimeZoneInfo]::Local)
            $repeatServerBefore2022 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -SqlCredential $repeatCredential
            $repeatTempdbInLocalTimeZone = @{ tempdb = [PSCustomObject]@{ CreateDate = $repeatStartInLocalTimeZone } }
            Add-Member -InputObject $repeatServerBefore2022 -NotePropertyName Databases -NotePropertyValue $repeatTempdbInLocalTimeZone -Force
            Add-Member -InputObject $repeatServerBefore2022 -NotePropertyName Version -NotePropertyValue ([version]"15.0.4430.1") -Force

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            foreach ($repeatServer in $repeatServerInInstanceTimeZone, $repeatServerBefore2022, $repeatAdminServer) {
                if ($repeatServer) {
                    $null = $repeatServer | Disconnect-DbaInstance
                }
            }
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $repeatLoginName -Force -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Counts a start in the repeated hour of the time zone of the instance as the second occurrence" {
            if (-not $repeatInstanceNamesTimeZone) {
                Set-ItResult -Skipped -Because "the instance names its time zone with CURRENT_TIMEZONE_ID() from SQL Server 2022 on"
            }
            $logStart = Get-Date
            $result = Get-DbaUptime -SqlInstance $repeatServerInInstanceTimeZone
            $getWarnings = $WarnVar
            $serverUtcTime = $repeatAdminServer.Query("SELECT SYSUTCDATETIME() AS ServerUtcTime").ServerUtcTime
            $expectedUptime = $serverUtcTime - [System.TimeZoneInfo]::ConvertTimeToUtc($repeatStartInInstanceTimeZone, $repeatInstanceTimeZone)
            $getWarnings | Should -BeNullOrEmpty
            @($result).Count | Should -Be 1
            $result.SqlStartTime.ToString() | Should -Be ([dbadatetime]$repeatStartInInstanceTimeZone).ToString()
            [math]::Abs(($result.SqlUptime - $expectedUptime).TotalSeconds) | Should -BeLessThan 120
            $commandMessages = Get-DbatoolsLog -FunctionName Get-DbaUptime | Where-Object Timestamp -ge $logStart
            ($commandMessages | Where-Object Message -like "Could not read sys.dm_os_sys_info*").Message | Should -BeLike "*in its time zone*"
            if ($repeatInstanceTimeZone.IsAmbiguousTime($repeatStartInInstanceTimeZone)) {
                ($commandMessages | Where-Object Message -like "SqlStartTime*").Message | Should -BeLike "*lies in the hour that repeats*"
            }
        }

        It "Counts a start in the repeated hour of the time zone of this computer as the second occurrence before SQL Server 2022" {
            $logStart = Get-Date
            $result = Get-DbaUptime -SqlInstance $repeatServerBefore2022
            $getWarnings = $WarnVar
            $serverUtcTime = $repeatAdminServer.Query("SELECT SYSUTCDATETIME() AS ServerUtcTime").ServerUtcTime
            $expectedUptime = $serverUtcTime - [System.TimeZoneInfo]::ConvertTimeToUtc($repeatStartInLocalTimeZone, [System.TimeZoneInfo]::Local)
            $getWarnings | Should -BeNullOrEmpty
            @($result).Count | Should -Be 1
            $result.SqlStartTime.ToString() | Should -Be ([dbadatetime]$repeatStartInLocalTimeZone).ToString()
            [math]::Abs(($result.SqlUptime - $expectedUptime).TotalSeconds) | Should -BeLessThan 120
            $commandMessages = Get-DbatoolsLog -FunctionName Get-DbaUptime | Where-Object Timestamp -ge $logStart
            ($commandMessages | Where-Object Message -like "Could not read sys.dm_os_sys_info*").Message | Should -BeLike "*in the time zone of this computer*"
            if ([System.TimeZoneInfo]::Local.IsAmbiguousTime($repeatStartInLocalTimeZone)) {
                ($commandMessages | Where-Object Message -like "SqlStartTime*").Message | Should -BeLike "*lies in the hour that repeats*"
            }
        }
    }
}