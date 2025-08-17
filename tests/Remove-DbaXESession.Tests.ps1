#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaXESession",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Session",
                "AllSessions",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $null = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $null = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Test Importing Session Template" {
        BeforeAll {
            $results = Import-DbaXESessionTemplate -SqlInstance $TestConfig.instance2 -Template 'Profiler TSQL Duration'
        }

        It "session should exist" {
            $results.Name | Should -BeExactly 'Profiler TSQL Duration'
        }

        It "session should no longer exist after removal" {
            $null = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session 'Profiler TSQL Duration' | Remove-DbaXESession
            $removedResults = Get-DbaXESession -SqlInstance $TestConfig.instance2 -Session 'Profiler TSQL Duration'
            $removedResults.Name | Should -BeNullOrEmpty
            $removedResults.Status | Should -BeNullOrEmpty
        }
    }
}