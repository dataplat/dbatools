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
    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaUptime -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlServer",
                "SqlUptime",
                "WindowsUptime",
                "SqlStartTime",
                "WindowsBootTime",
                "SinceSqlStart",
                "SinceWindowsBoot"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "SqlStartTime property is DbaDateTime type" {
            $result.SqlStartTime | Should -BeOfType DbaDateTime
        }

        It "WindowsBootTime property is DbaDateTime type" {
            $result.WindowsBootTime | Should -BeOfType DbaDateTime
        }

        It "SqlUptime property is TimeSpan type" {
            $result.SqlUptime | Should -BeOfType TimeSpan
        }

        It "WindowsUptime property is TimeSpan type" {
            $result.WindowsUptime | Should -BeOfType TimeSpan
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
}