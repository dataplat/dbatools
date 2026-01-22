#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbQueryStoreOption",
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
                "ExcludeDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.QueryStoreOptions]
        }

        It "Has the expected default display properties for all versions" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'ActualState',
                'DataFlushIntervalInSeconds',
                'StatisticsCollectionIntervalInMinutes',
                'MaxStorageSizeInMB',
                'CurrentStorageSizeInMB',
                'QueryCaptureMode',
                'SizeBasedCleanupMode',
                'StaleQueryThresholdInDays'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has dbatools-added properties" {
            $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result[0].PSObject.Properties.Name | Should -Contain 'InstanceName'
            $result[0].PSObject.Properties.Name | Should -Contain 'SqlInstance'
            $result[0].PSObject.Properties.Name | Should -Contain 'Database'
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>