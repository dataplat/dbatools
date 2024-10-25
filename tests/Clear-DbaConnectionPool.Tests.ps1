#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Clear-DbaConnectionPool" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Clear-DbaConnectionPool
            $expected = $TestConfig.CommonParameters

            $expected += @(
                "ComputerName",
                "Credential",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Clear-DbaConnectionPool" -Tag "IntegrationTests" {
    Context "When clearing connection pool" {
        It "Doesn't throw" {
            { Clear-DbaConnectionPool } | Should -Not -Throw
        }
    }
}
