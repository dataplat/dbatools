#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaFilestream",
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
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Getting FileStream Level" {
        It "Should have changed the FileStream Level" {
            $results = Get-DbaFilestream -SqlInstance $TestConfig.InstanceSingle
            $results.InstanceAccess | Should -BeIn "Disabled", "T-SQL access enabled", "Full access enabled"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaFilestream -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "InstanceAccess", "ServiceAccess", "ServiceShareName")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has all expected properties available" {
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "InstanceAccess", "ServiceAccess", "ServiceShareName", "InstanceAccessLevel", "ServiceAccessLevel")
            foreach ($prop in $expectedProps) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}