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

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaUptime -SqlInstance $TestConfig.InstanceMulti1
        }

        It "Returns output of the expected type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result - CIM/WMI connectivity may not be available" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result - CIM/WMI connectivity may not be available" }
            $expectedProps = @("ComputerName", "InstanceName", "SqlServer", "SqlUptime", "WindowsUptime", "SqlStartTime", "WindowsBootTime", "SinceSqlStart", "SinceWindowsBoot")
            foreach ($prop in $expectedProps) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}