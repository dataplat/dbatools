#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "LogNumber",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command gets agent log" {
        BeforeAll {
            $results = Get-DbaAgentLog -SqlInstance $TestConfig.instance2
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Results contain SQLServerAgent version" {
            ($results.text -like "`[100`] Microsoft SQLServerAgent version*").Count -gt 0 | Should -Be $true
        }

        It "LogDate is a DateTime type" {
            $($results | Select-Object -first 1).LogDate | Should -BeOfType DateTime
        }
    }

    Context "Command gets current agent log using LogNumber parameter" {
        BeforeAll {
            $logNumberResults = Get-DbaAgentLog -SqlInstance $TestConfig.instance2 -LogNumber 0
        }

        It "Results are not empty" {
            $logNumberResults | Should -Not -BeNullOrEmpty
        }
    }
}
