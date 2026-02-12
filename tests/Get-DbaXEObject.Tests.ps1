#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaXEObject",
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
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $result = @(Get-DbaXEObject -SqlInstance $TestConfig.InstanceSingle)
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType System.Data.DataRow
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $excludedProps = @(
                "ComputerName",
                "InstanceName",
                "ObjectTypeRaw"
            )
            foreach ($prop in $excludedProps) {
                $defaultProps | Should -Not -Contain $prop -Because "property '$prop' should be excluded from the default display set"
            }
            $expectedDefaults = @(
                "SqlInstance",
                "PackageName",
                "ObjectType",
                "TargetName",
                "Description"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}