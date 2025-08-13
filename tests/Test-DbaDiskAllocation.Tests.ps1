#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-DbaDiskAllocation",
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
                "ComputerName",
                "NoSqlCheck",
                "SqlCredential",
                "Credential",
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
            $results = Test-DbaDiskAllocation -ComputerName $TestConfig.instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result not using sql" {
            $results = Test-DbaDiskAllocation -NoSqlCheck -ComputerName $TestConfig.instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}