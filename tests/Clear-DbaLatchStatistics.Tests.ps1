#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Clear-DbaLatchStatistics" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Clear-DbaLatchStatistics
            $expectedParameters = $TestConfig.CommonParameters

            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $actualParameters | Should -BeNullOrEmpty
        }
    }
}

Describe "Clear-DbaLatchStatistics" -Tag "IntegrationTests" {
    Context "Command executes properly and returns proper info" {
        BeforeAll {
            $splatClearLatch = @{
                SqlInstance = $TestConfig.instance1
                Confirm = $false
            }
            $results = Clear-DbaLatchStatistics @splatClearLatch
        }

        It "Returns success" {
            $results.Status | Should -Be 'Success'
        }
    }
}
