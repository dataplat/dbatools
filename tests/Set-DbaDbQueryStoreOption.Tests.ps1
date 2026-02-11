#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbQueryStoreOption",
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
                "AllDatabases",
                "State",
                "FlushInterval",
                "CollectionInterval",
                "MaxSize",
                "CaptureMode",
                "CleanupMode",
                "StaleQueryThreshold",
                "MaxPlansPerQuery",
                "WaitStatsCaptureMode",
                "EnableException",
                "CustomCapturePolicyExecutionCount",
                "CustomCapturePolicyTotalCompileCPUTimeMS",
                "CustomCapturePolicyTotalExecutionCPUTimeMS",
                "CustomCapturePolicyStaleThresholdHours"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Where-Object Name -Match "dbatoolsci" | Remove-DbaDatabase
        New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Name dbatoolsciqs
    }
    AfterAll {
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Where-Object Name -Match "dbatoolsci" | Remove-DbaDatabase
    }
    Context "When testing Query Store functionality" {
        It "should warn for SQL Server versions below 2016" {
            foreach ($instance in ($TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2)) {
                $server = Connect-DbaInstance -SqlInstance $instance
                $results = Get-DbaDbQueryStoreOption -SqlInstance $server -WarningVariable warning 3>&1

                if ($server.VersionMajor -lt 13) {
                    $warning | Should -Not -BeNullOrEmpty
                }
            }
        }

        It "should return valid results for supported SQL Server versions" {
            foreach ($instance in ($TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2)) {
                $server = Connect-DbaInstance -SqlInstance $instance
                $results = Get-DbaDbQueryStoreOption -SqlInstance $server -WarningVariable warning 3>&1

                if ($server.VersionMajor -ge 13) {
                    $result = $results | Where-Object Database -eq dbatoolsciqs
                    if ($server.VersionMajor -lt 16) {
                        $result.ActualState | Should -Be "Off"
                    } else {
                        $result.ActualState | Should -Be "ReadWrite"
                    }
                    $result.MaxStorageSizeInMB | Should -BeGreaterThan 1
                }
            }
        }

        It "should change the specified param to the new value" {
            foreach ($instance in ($TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2)) {
                $server = Connect-DbaInstance -SqlInstance $instance
                if ($server.VersionMajor -ge 13) {
                    $results = Set-DbaDbQueryStoreOption -SqlInstance $instance -Database dbatoolsciqs -FlushInterval 901 -State ReadWrite
                    $results.DataFlushIntervalInSeconds | Should -Be 901
                }
            }
        }

        It "should only get one database when specified" {
            foreach ($instance in ($TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2)) {
                $server = Connect-DbaInstance -SqlInstance $instance
                if ($server.VersionMajor -ge 13) {
                    $results = Get-DbaDbQueryStoreOption -SqlInstance $instance -Database dbatoolsciqs
                    $results.Count | Should -Be 1
                    $results.Database | Should -Be "dbatoolsciqs"
                }
            }
        }

        It "should not get excluded database" {
            foreach ($instance in ($TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2)) {
                $server = Connect-DbaInstance -SqlInstance $instance
                if ($server.VersionMajor -ge 13) {
                    $results = Get-DbaDbQueryStoreOption -SqlInstance $instance -ExcludeDatabase dbatoolsciqs
                    $result = $results | Where-Object Database -eq dbatoolsciqs
                    $result.Count | Should -Be 0
                }
            }
        }
    }

    Context "Output validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            if ($server.VersionMajor -ge 13) {
                $result = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceMulti1 -Database dbatoolsciqs -State ReadWrite -FlushInterval 900
            }
        }

        It "Returns output of the documented type" {
            if ($server.VersionMajor -lt 13) { Set-ItResult -Skipped -Because "Query Store requires SQL Server 2016+" }
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.QueryStoreOptions"
        }

        It "Has the expected default display properties" {
            if ($server.VersionMajor -lt 13) { Set-ItResult -Skipped -Because "Query Store requires SQL Server 2016+" }
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ActualState",
                "DataFlushIntervalInSeconds",
                "StatisticsCollectionIntervalInMinutes",
                "MaxStorageSizeInMB",
                "CurrentStorageSizeInMB",
                "QueryCaptureMode",
                "SizeBasedCleanupMode",
                "StaleQueryThresholdInDays"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}