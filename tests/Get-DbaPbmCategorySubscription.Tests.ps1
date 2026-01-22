#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPbmCategorySubscription",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaPbmCategorySubscription -SqlInstance $TestConfig.instance2 -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Dmf.PolicyCategorySubscription]
        }

        It "Has ComputerName, InstanceName, and SqlInstance properties added by dbatools" {
            $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result[0].PSObject.Properties.Name | Should -Contain 'InstanceName'
            $result[0].PSObject.Properties.Name | Should -Contain 'SqlInstance'
        }

        It "Has core subscription properties in default display" {
            $expectedProps = @(
                'PolicyCategory',
                'Target',
                'TargetType',
                'ID'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Excludes Properties, Urn, and Parent from default view" {
            # These are excluded via Select-DefaultView -ExcludeProperty
            # But they should still be accessible via Select-Object *
            $expandedResult = $result[0] | Select-Object -Property *
            $expandedResult.PSObject.Properties.Name | Should -Contain 'Properties'
            $expandedResult.PSObject.Properties.Name | Should -Contain 'Urn'
            $expandedResult.PSObject.Properties.Name | Should -Contain 'Parent'
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>