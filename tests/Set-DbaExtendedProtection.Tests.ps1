#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaExtendedProtection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Value",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Default set and returns '0 - Off'" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -EnableException
            $results.ExtendedProtection | Should -Be "0 - Off"
        }
    }
    Context "Command works when passed different values" {
        BeforeAll {
            Mock Test-ShouldProcess { $false } -ModuleName dbatools
            Mock Invoke-ManagedComputerCommand -MockWith {
                param (
                    $ComputerName,
                    $Credential,
                    $ScriptBlock,
                    $EnableException
                )
                $server = [DbaInstanceParameter[]]$TestConfig.InstanceSingle
                @{
                    DisplayName        = "SQL Server ($($server.InstanceName))"
                    AdvancedProperties = @(
                        @{
                            Name  = "REGROOT"
                            Value = "Software\Microsoft\Microsoft SQL Server\MSSQL10_50.SQL2008R2SP2"
                        }
                    )
                }
            } -ModuleName dbatools
        }
        It "Set explicitly to '0 - Off' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value Off -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 0"
        }
        It "Set explicitly to '0 - Off' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value 0 -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 0"
        }

        It "Set explicitly to '1 - Allowed' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value Allowed -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 1"
        }
        It "Set explicitly to '1 - Allowed' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value 1 -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 1"
        }

        It "Set explicitly to '2 - Required' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value Required -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 2"
        }
        It "Set explicitly to '2 - Required' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.InstanceSingle -Value 2 -EnableException -Verbose 4>&1
            $results[-1] | Should -BeLike "*Value: 2"
        }
    }
}