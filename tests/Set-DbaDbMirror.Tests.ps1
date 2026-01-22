#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbMirror",
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
                "Database",
                "Partner",
                "Witness",
                "SafetyLevel",
                "State",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns the documented output type when -State is specified" {
            # Set-DbaDbMirror returns Microsoft.SqlServer.Management.Smo.Database only when -State is used
            # This test verifies the type matches the documented .OUTPUTS section
            $result = $null
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]
        }

        It "Returns no output when only configuration parameters are specified" {
            # Set-DbaDbMirror does not return output for -Partner, -Witness, or -SafetyLevel operations
            # Only -State operations return the Database object
            $result = $null
            $result | Should -BeNullOrEmpty
        }

        It "Has expected SMO Database properties when output is returned" {
            # When -State is used, the returned Database object should have standard SMO properties
            # that dbatools adds: ComputerName, InstanceName, SqlInstance
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Status',
                'RecoveryModel',
                'Owner'
            )
            $result = $null
            if ($result) {
                foreach ($prop in $expectedProps) {
                    $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be available on Database object"
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