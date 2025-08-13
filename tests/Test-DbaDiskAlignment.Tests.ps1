#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDiskAlignment",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "SqlCredential",
                "NoSqlCheck",
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
        It "Should return a result" {
            $results = Test-DbaDiskAlignment -ComputerName $TestConfig.DbaToolsCi_Computer
            $results | Should -Not -Be $null
        }

        It "Should return a result not using sql" {
            $results = Test-DbaDiskAlignment -NoSqlCheck -ComputerName $TestConfig.DbaToolsCi_Computer
            $results | Should -Not -Be $null
        }
    }
}
