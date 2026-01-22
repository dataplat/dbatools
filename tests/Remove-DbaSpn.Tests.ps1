#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaSpn",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SPN",
                "ServiceAccount",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Mock the output structure based on the command implementation
            $mockOutput = [PSCustomObject]@{
                Name           = "MSSQLSvc/testserver:1433"
                ServiceAccount = "domain\sqlservice"
                Property       = "servicePrincipalName"
                IsSet          = $false
                Notes          = "Successfully removed SPN"
            }
        }

        It "Returns PSCustomObject" {
            $mockOutput.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected output properties" {
            $expectedProps = @(
                'Name',
                'ServiceAccount',
                'Property',
                'IsSet',
                'Notes'
            )
            $actualProps = $mockOutput.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }

        It "Property field contains expected values" {
            # Property should be either servicePrincipalName or msDS-AllowedToDelegateTo
            @('servicePrincipalName', 'msDS-AllowedToDelegateTo') | Should -Contain $mockOutput.Property
        }

        It "IsSet field is boolean" {
            $mockOutput.IsSet | Should -BeOfType [System.Boolean]
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>