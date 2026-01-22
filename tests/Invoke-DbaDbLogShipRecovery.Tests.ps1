#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbLogShipRecovery",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "SqlCredential",
                "NoRecovery",
                "EnableException",
                "Force",
                "InputObject",
                "Delay"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns PSCustomObject" {
            $command = Get-Command $CommandName
            $command.OutputType.Name | Should -Contain 'PSCustomObject'
        }

        It "Has the expected output properties documented" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'RecoverResult',
                'Comment'
            )
            $help = Get-Help $CommandName
            $outputSection = $help.returnValues.returnValue | Where-Object { $_.type.name -eq 'PSCustomObject' }
            $outputSection | Should -Not -BeNullOrEmpty -Because "command should document PSCustomObject output type"

            foreach ($prop in $expectedProps) {
                $help.Text | Should -Match $prop -Because "property '$prop' should be documented in help"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>