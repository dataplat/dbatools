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

        It "Returns positive uptime TimeSpans for $($result.SqlServer)" {
            # On checkpoint-resumed lab VMs the OS LastBootTime can move PAST tempdb's
            # CreateDate (the service keeps running across a resume), so the classic
            # "Windows uptime exceeds SQL uptime" ordering is not a valid invariant
            # here - assert the honest shape instead.
            foreach ($result in $results) {
                $result.SqlUptime | Should -BeOfType TimeSpan
                $result.WindowsUptime | Should -BeOfType TimeSpan
                $result.SqlUptime.TotalSeconds | Should -BeGreaterThan 0
                $result.WindowsUptime.TotalSeconds | Should -BeGreaterThan 0
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
}