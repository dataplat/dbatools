#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaOperator",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $command = Get-Command $CommandName
            $command.OutputType.Name | Should -Contain 'PSCustomObject'
        }

        It "Has the expected properties documented in .OUTPUTS" {
            $expectedProps = @(
                'AvailabilityGroup',
                'Replica',
                'OperatorName',
                'Status',
                'EmailAddress'
            )
            $command = Get-Command $CommandName
            $helpOutput = Get-Help $CommandName
            $outputSection = $helpOutput.returnValues.returnValue.type.name
            $outputSection | Should -Be 'PSCustomObject'
            foreach ($prop in $expectedProps) {
                $helpOutput.description.Text | Should -Match $prop -Because "property '$prop' should be documented in .OUTPUTS"
            }
        }
    }
}
