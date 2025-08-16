#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgHadr",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Validate parameters" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# $TestConfig.instance3 is used for Availability Group tests and needs Hadr service setting enabled

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $results = Get-DbaAgHadr -SqlInstance $TestConfig.instance3
    }

    Context "Validate output" {
        It "returns the correct properties" {
            $results.IsHadrEnabled | Should -Be $true
        }
    }
} #$TestConfig.instance2 for appveyor