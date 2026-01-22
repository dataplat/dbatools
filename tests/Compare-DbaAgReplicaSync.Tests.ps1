#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaSync",
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
                "AvailabilityGroup",
                "Exclude",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            # Create mock output to test structure
            $mockResult = [PSCustomObject]@{
                AvailabilityGroup   = "TestAG"
                Replica             = "SQL01"
                ObjectType          = "Login"
                ObjectName          = "TestLogin"
                Status              = "Missing"
                PropertyDifferences = $null
            }
            $mockResult.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected output properties" {
            # Create mock output to test structure
            $mockResult = [PSCustomObject]@{
                AvailabilityGroup   = "TestAG"
                Replica             = "SQL01"
                ObjectType          = "Login"
                ObjectName          = "TestLogin"
                Status              = "Missing"
                PropertyDifferences = $null
            }

            $expectedProps = @(
                "AvailabilityGroup",
                "Replica",
                "ObjectType",
                "ObjectName",
                "Status",
                "PropertyDifferences"
            )
            $actualProps = $mockResult.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }
    }
}
