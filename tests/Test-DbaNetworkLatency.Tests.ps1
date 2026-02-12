#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaNetworkLatency",
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
                "Query",
                "Count",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns proper info" {
        BeforeAll {
            $pipelineResults = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Test-DbaNetworkLatency -EnableException
            $parameterResults = Test-DbaNetworkLatency -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -EnableException
        }

        It "returns two objects when using pipeline" {
            $pipelineResults.Count | Should -Be 2
        }

        It "executes 3 times by default" {
            $parameterResults.ExecutionCount | Should -Be 3, 3
        }

        It "has the correct properties" {
            $result = $parameterResults | Select-Object -First 1
            $expectedPropsDefault = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ExecutionCount",
                "Total",
                "Average",
                "ExecuteOnlyTotal",
                "ExecuteOnlyAverage",
                "NetworkOnlyTotal"
            )
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedPropsDefault | Sort-Object)
        }

        Context "Output validation" {
            It "Returns output of the expected type" {
                $parameterResults | Should -Not -BeNullOrEmpty
                $parameterResults[0] | Should -BeOfType PSCustomObject
            }

            It "Has the expected default display properties" {
                $defaultProps = $parameterResults[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                $expectedDefaults = @(
                    "ComputerName",
                    "InstanceName",
                    "SqlInstance",
                    "ExecutionCount",
                    "Total",
                    "Average",
                    "ExecuteOnlyTotal",
                    "ExecuteOnlyAverage",
                    "NetworkOnlyTotal"
                )
                foreach ($prop in $expectedDefaults) {
                    $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
                }
            }

            It "Has working alias properties" {
                $parameterResults[0].PSObject.Properties["ExecutionCount"] | Should -Not -BeNullOrEmpty
                $parameterResults[0].PSObject.Properties["ExecutionCount"].MemberType | Should -Be "AliasProperty"
                $parameterResults[0].PSObject.Properties["Average"] | Should -Not -BeNullOrEmpty
                $parameterResults[0].PSObject.Properties["Average"].MemberType | Should -Be "AliasProperty"
                $parameterResults[0].PSObject.Properties["ExecuteOnlyAverage"] | Should -Not -BeNullOrEmpty
                $parameterResults[0].PSObject.Properties["ExecuteOnlyAverage"].MemberType | Should -Be "AliasProperty"
            }
        }
    }
}