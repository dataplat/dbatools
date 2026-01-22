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

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaXEObject -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'PackageName',
                'ObjectType',
                'TargetName',
                'Description'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties available via Select-Object *" {
            $additionalProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'ObjectTypeRaw'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $additionalProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be accessible"
            }
        }
    }

    Context "Output with -Type filter" {
        BeforeAll {
            $result = Get-DbaXEObject -SqlInstance $TestConfig.instance1 -Type Event, Action -EnableException
        }

        It "Returns the same output structure when filtered" {
            $expectedProps = @(
                'PackageName',
                'ObjectType',
                'TargetName',
                'Description'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "filtered output should have same structure"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>