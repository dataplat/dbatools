#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaCredential",
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
            $outputType = $command.OutputType.Name
            $outputType | Should -Be 'PSCustomObject'
        }

        It "Has the expected output properties documented" {
            $expectedProps = @(
                'AvailabilityGroup',
                'Replica',
                'CredentialName',
                'Status',
                'Identity'
            )
            $help = Get-Help $CommandName
            $outputSection = $help.returnValues.returnValue | Where-Object { $_.type.name -eq 'PSCustomObject' }
            $outputSection | Should -Not -BeNullOrEmpty -Because "command should document PSCustomObject output type"
            
            foreach ($prop in $expectedProps) {
                $help.returnValues.returnValue.description.Text | Should -Match $prop -Because "property '$prop' should be documented in .OUTPUTS"
            }
        }
    }
}
