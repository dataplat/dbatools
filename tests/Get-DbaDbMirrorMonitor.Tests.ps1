#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMirrorMonitor",
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
                "InputObject",
                "Update",
                "LimitResults",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Get-DbaDbMirrorMonitor requires a mirrored database to return results
            # This test validates the output structure when results are available
            $result = Get-DbaDbMirrorMonitor -SqlInstance $TestConfig.instance1 -EnableException -ErrorAction SilentlyContinue
        }

        It "Returns PSCustomObject" {
            if ($result) {
                $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
            } else {
                Set-ItResult -Skipped -Because "No mirrored databases found for testing"
            }
        }

        It "Has the expected properties" {
            if ($result) {
                $expectedProps = @(
                    'ComputerName',
                    'InstanceName',
                    'SqlInstance',
                    'DatabaseName',
                    'Role',
                    'MirroringState',
                    'WitnessStatus',
                    'LogGenerationRate',
                    'UnsentLog',
                    'SendRate',
                    'UnrestoredLog',
                    'RecoveryRate',
                    'TransactionDelay',
                    'TransactionsPerSecond',
                    'AverageDelay',
                    'TimeRecorded',
                    'TimeBehind',
                    'LocalTime'
                )
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
                }
            } else {
                Set-ItResult -Skipped -Because "No mirrored databases found for testing"
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>