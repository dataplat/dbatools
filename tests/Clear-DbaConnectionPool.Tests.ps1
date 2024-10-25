#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Clear-DbaConnectionPool" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Clear-DbaConnectionPool
            $expectedParameters = $TestConfig.CommonParameters

            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $command.Parameters.Keys | Should -BeNullOrEmpty
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
