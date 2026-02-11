#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaOptimizeForAdHoc",
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
    Context "Command actually works" {
        BeforeAll {
            $results = Test-DbaOptimizeForAdHoc -SqlInstance $TestConfig.InstanceSingle
        }

        It "Should return result for the server" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return 'CurrentOptimizeAdHoc' property as int" {
            $results.CurrentOptimizeAdHoc | Should -BeOfType System.Int32
        }

        It "Should return 'RecommendedOptimizeAdHoc' property as int" {
            $results.RecommendedOptimizeAdHoc | Should -BeOfType System.Int32
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Test-DbaOptimizeForAdHoc -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "CurrentOptimizeAdHoc",
                "RecommendedOptimizeAdHoc",
                "Notes"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}