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
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Get the agent log for testing
        $agentLogResults = Get-DbaAgentLog -SqlInstance $TestConfig.instance2
        $currentLogResults = Get-DbaAgentLog -SqlInstance $TestConfig.instance2 -LogNumber 0

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    Context "Command gets agent log" {
        It "Results are not empty" {
            $agentLogResults | Should -Not -BeNullOrEmpty
        }

        It "Results contain SQLServerAgent version" {
            $agentLogResults.text -like "`[100`] Microsoft SQLServerAgent version*" | Should -Be $true
        }

        It "LogDate is a DateTime type" {
            $agentLogResults[0].LogDate | Should -BeOfType DateTime
        }
    }

    Context "Command gets current agent log using LogNumber parameter" {
        It "Results are not empty" {
            $currentLogResults | Should -Not -BeNullOrEmpty
        }
    }
}