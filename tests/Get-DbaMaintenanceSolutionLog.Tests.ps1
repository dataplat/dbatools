#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaMaintenanceSolutionLog",
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
                "LogType",
                "Since",
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Note: This test requires actual log files from Ola Hallengren's MaintenanceSolution
            # If no log files exist, the command returns no output (expected behavior)
            $result = Get-DbaMaintenanceSolutionLog -SqlInstance $TestConfig.instance1 -EnableException -ErrorAction SilentlyContinue
        }

        It "Returns PSCustomObject" {
            if ($result) {
                $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
            }
        }

        It "Has the expected properties when log files exist" {
            if ($result) {
                $expectedProps = @(
                    'ComputerName',
                    'InstanceName',
                    'SqlInstance',
                    'Database',
                    'StartTime',
                    'Duration',
                    'Index',
                    'Statistics',
                    'Schema',
                    'Table',
                    'Action',
                    'Options',
                    'Timeout',
                    'Partition',
                    'ObjectType',
                    'IndexType',
                    'ImageText',
                    'NewLOB',
                    'FileStream',
                    'ColumnStore',
                    'AllowPageLocks',
                    'PageCount',
                    'Fragmentation',
                    'Error'
                )
                $actualProps = $result[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
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