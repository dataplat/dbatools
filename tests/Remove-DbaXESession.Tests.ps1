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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session 'Profiler TSQL Duration' | Remove-DbaXESession

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session 'Profiler TSQL Duration' | Remove-DbaXESession

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Test Importing Session Template" {
        BeforeAll {
            $results = Import-DbaXESessionTemplate -SqlInstance $TestConfig.InstanceSingle -Template 'Profiler TSQL Duration'
        }

        It "session should exist" {
            $results.Name | Should -BeExactly 'Profiler TSQL Duration'
        }

        It "session should no longer exist after removal" {
            $null = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session 'Profiler TSQL Duration' | Remove-DbaXESession
            $removedResults = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session 'Profiler TSQL Duration'
            $removedResults.Name | Should -BeNullOrEmpty
            $removedResults.Status | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $null = Import-DbaXESessionTemplate -SqlInstance $TestConfig.InstanceSingle -Template 'Profiler TSQL Duration'
            $result = Get-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session 'Profiler TSQL Duration' | Remove-DbaXESession
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Session", "Status")
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}