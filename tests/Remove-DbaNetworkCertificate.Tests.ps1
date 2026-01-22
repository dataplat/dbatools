#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaNetworkCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Note: This test validates output structure without actually removing certificates
            # The command supports -WhatIf, so we test the expected output properties
        }

        It "Should return PSCustomObject type" {
            $command = Get-Command $CommandName
            $command.OutputType.Name | Should -Contain 'PSCustomObject'
        }

        It "Should have the expected output properties documented" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'ServiceAccount',
                'RemovedThumbprint'
            )
            
            $help = Get-Help $CommandName -Full
            $outputSection = $help.returnValues.returnValue[0].type.name
            
            $outputSection | Should -Be 'PSCustomObject' -Because "output type should be documented as PSCustomObject"
            
            # Verify all properties are documented in the OUTPUTS section
            foreach ($prop in $expectedProps) {
                $help.returnValues.returnValue.description.Text | Should -Match $prop -Because "property '$prop' should be documented in .OUTPUTS"
            }
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>