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

    Context "Output validation" {
        BeforeAll {
            # Use a high threshold to avoid actually clearing the plan cache
            $result = Clear-DbaPlanCache -SqlInstance $TestConfig.InstanceSingle -Threshold 10240
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $result | Should -Not -BeNullOrEmpty
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Size", "Status")
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}