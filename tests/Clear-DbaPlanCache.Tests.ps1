#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Clear-DbaPlanCache",
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
                "Threshold",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When not clearing plan cache" {
        BeforeAll {
            # Make plan cache way higher than likely for a test rig
            $threshold = 10240
        }

        It "Returns correct datatypes" {
            $results = Clear-DbaPlanCache -SqlInstance $TestConfig.InstanceSingle -Threshold $threshold
            $results.Size | Should -BeOfType [dbasize]
            $results.Status | Should -Match "below"
        }

        It "Supports piping" {
            $results = Get-DbaPlanCache -SqlInstance $TestConfig.InstanceSingle | Clear-DbaPlanCache -Threshold $threshold
            $results.Size | Should -BeOfType [dbasize]
            $results.Status | Should -Match "below"
        }
    }

    Context "When clearing plan cache" {
        It "Returns one result per instance" {
            # A threshold of 0 clears the cache whatever its size
            $results = Clear-DbaPlanCache -SqlInstance $TestConfig.InstanceSingle -Threshold 0
            # Counts the output itself, $results.Status would skip a $null written by the command
            @($results).Count | Should -Be 1
            $results.Status | Should -Be "Plan cache cleared"
        }
    }
}