#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Clear-DbaWaitStatistics" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Clear-DbaWaitStatistics
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Clear-DbaWaitStatistics" -Tag "IntegrationTests" {
    Context "Command executes properly and returns proper info" {
        BeforeAll {
            $results = Clear-DbaWaitStatistics -SqlInstance $TestConfig.instance1 -Confirm:$false
        }

        It "Returns success" {
            $results.Status | Should -Be 'Success'
        }
    }
}
