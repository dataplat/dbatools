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

    Context "Output Validation" {
        BeforeAll {
            $instance = $TestConfig.InstanceMulti1
            $server = Connect-DbaInstance -SqlInstance $instance
        }

        It "Returns the documented output type" {
            if ($server.VersionMajor -ge 13) {
                $result = Set-DbaDbQueryStoreOption -SqlInstance $instance -Database dbatoolsciqs -FlushInterval 900 -EnableException
                $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.QueryStoreOptions]
            }
        }

        It "Has the expected base default display properties (SQL 2016+)" {
            if ($server.VersionMajor -ge 13) {
                $result = Set-DbaDbQueryStoreOption -SqlInstance $instance -Database dbatoolsciqs -FlushInterval 900 -EnableException
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
                $actualProps = $result.PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
                }
            }
        }

        It "Has MaxPlansPerQuery and WaitStatsCaptureMode properties for SQL 2017+" {
            if ($server.VersionMajor -ge 14) {
                $result = Set-DbaDbQueryStoreOption -SqlInstance $instance -Database dbatoolsciqs -FlushInterval 900 -EnableException
                $result.PSObject.Properties.Name | Should -Contain 'MaxPlansPerQuery'
                $result.PSObject.Properties.Name | Should -Contain 'WaitStatsCaptureMode'
            }
        }

        It "Has Custom Capture Policy properties for SQL 2019+" {
            if ($server.VersionMajor -ge 15) {
                $result = Set-DbaDbQueryStoreOption -SqlInstance $instance -Database dbatoolsciqs -FlushInterval 900 -EnableException
                $result.PSObject.Properties.Name | Should -Contain 'CustomCapturePolicyExecutionCount'
                $result.PSObject.Properties.Name | Should -Contain 'CustomCapturePolicyTotalCompileCPUTimeMS'
                $result.PSObject.Properties.Name | Should -Contain 'CustomCapturePolicyTotalExecutionCPUTimeMS'
                $result.PSObject.Properties.Name | Should -Contain 'CustomCapturePolicyStaleThresholdHours'
            }
        }
    }
}