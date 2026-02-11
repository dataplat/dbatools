#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSpinLockStatistic",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When retrieving spinlock statistics" {
        It "Returns spinlock contention metrics from SQL Server" {
            $results = @(Get-DbaSpinLockStatistic -SqlInstance $TestConfig.InstanceSingle)
            $results.Count | Should -BeGreaterThan 0
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = @(Get-DbaSpinLockStatistic -SqlInstance $TestConfig.InstanceSingle)
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $result | Should -Not -BeNullOrEmpty
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "SpinLockName",
                "Collisions",
                "Spins",
                "SpinsPerCollision",
                "SleepTime",
                "Backoffs"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}