#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaExtendedProtection",
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
                "Credential",
                "Value",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Default set and returns '0 - Off'" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.instance1 -EnableException *>$null
            $results.ExtendedProtection -eq "0 - Off"
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
                $server = [DbaInstanceParameter[]]$TestConfig.instance1
                @{
                    DisplayName        = "SQL Server ($($instance.InstanceName))"
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
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.instance1 -Value Off -EnableException -Verbose 4>&1
            $results[-1] = "Value: 0"
        }
        It "Set explicitly to '0 - Off' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.instance1 -Value 0 -EnableException -Verbose 4>&1
            $results[-1] = "Value: 0"
        }

        It "Set explicitly to '1 - Allowed' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.instance1 -Value Allowed -EnableException -Verbose 4>&1
            $results[-1] = "Value: 1"
        }
        It "Set explicitly to '1 - Allowed' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.instance1 -Value 1 -EnableException -Verbose 4>&1
            $results[-1] = "Value: 1"
        }

        It "Set explicitly to '2 - Required' using text" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.instance1 -Value Required -EnableException -Verbose 4>&1
            $results[-1] = "Value: 2"
        }
        It "Set explicitly to '2 - Required' using number" {
            $results = Set-DbaExtendedProtection -SqlInstance $TestConfig.instance1 -Value 2 -EnableException -Verbose 4>&1
            $results[-1] = "Value: 2"
        }
    }
}