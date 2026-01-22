#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgReplica",
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
                "Replica",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $result = [PSCustomObject]@{
                ComputerName      = "Server1"
                InstanceName      = "MSSQLSERVER"
                SqlInstance       = "Server1"
                AvailabilityGroup = "AG1"
                Replica           = "Server2"
                Status            = "Removed"
            }
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected output properties" {
            $result = [PSCustomObject]@{
                ComputerName      = "Server1"
                InstanceName      = "MSSQLSERVER"
                SqlInstance       = "Server1"
                AvailabilityGroup = "AG1"
                Replica           = "Server2"
                Status            = "Removed"
            }
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "AvailabilityGroup",
                "Replica",
                "Status"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }
    }
}
