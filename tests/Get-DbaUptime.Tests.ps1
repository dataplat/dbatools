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
            $tempdbRow = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query "SELECT create_date AS CreateDate, GETDATE() AS ServerTime FROM sys.databases WHERE database_id = 2"
            $expectedUptime = New-TimeSpan -Start $tempdbRow.CreateDate -End $tempdbRow.ServerTime
            $WarnVar | Should -BeNullOrEmpty
            @($result).Count | Should -Be 1
            [math]::Abs(($result.SqlUptime - $expectedUptime).TotalSeconds) | Should -BeLessThan 120
        }
    }
}