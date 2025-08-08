#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Clear-DbaPlanCache",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Threshold",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
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
            $results = Clear-DbaPlanCache -SqlInstance $TestConfig.instance1 -Threshold $threshold
            $results.Size | Should -BeOfType [dbasize]
            $results.Status | Should -Match "below"
        }

        It "Supports piping" {
            $results = Get-DbaPlanCache -SqlInstance $TestConfig.instance1 | Clear-DbaPlanCache -Threshold $threshold
            $results.Size | Should -BeOfType [dbasize]
            $results.Status | Should -Match "below"
        }
    }
}
