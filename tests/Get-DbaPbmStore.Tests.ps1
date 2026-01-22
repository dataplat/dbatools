#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPbmStore",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaPbmStore -SqlInstance $TestConfig.instance2 -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.DMF.PolicyStore]
        }

        It "Has the expected dbatools-added properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be added by dbatools"
            }
        }

        It "Excludes documented properties from default display" {
            $excludedProps = @(
                'SqlStoreConnection',
                'ConnectionContext',
                'Properties',
                'Urn',
                'Parent',
                'DomainInstanceName',
                'Metadata',
                'IdentityKey',
                'Name'
            )
            # These properties should exist but be excluded from default view
            $defaultView = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            if ($defaultView) {
                foreach ($prop in $excludedProps) {
                    $defaultView | Should -Not -Contain $prop -Because "property '$prop' should be excluded from default display"
                }
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>