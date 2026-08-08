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

    Context "When a system database is named explicitly" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $serverMulti1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Warns about master and tempdb instead of doing nothing at all" {
            $resultsSystemDb = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceMulti1 -Database master, tempdb -State ReadWrite -WarningVariable warnSystemDb
            $resultsSystemDb | Should -BeNullOrEmpty
            $warnSystemDb -join "`n" | Should -Match "Query Store cannot be enabled on system database master"
            $warnSystemDb -join "`n" | Should -Match "Query Store cannot be enabled on system database tempdb"
        }

        It "Configures model from SQL Server 2022 on and warns about it before that" {
            if ($serverMulti1.VersionMajor -ge 16) {
                # Query Store on model decides the defaults of every database created afterwards, so the original
                # value is restored here rather than in an AfterAll that a failing assertion would reach too late.
                $originalThreshold = (Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceMulti1 -Database model).StaleQueryThresholdInDays
                try {
                    $resultsModel = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceMulti1 -Database model -StaleQueryThreshold 45 -WarningVariable warnModel
                    $resultsModel.Database | Should -Be "model"
                    $resultsModel.StaleQueryThresholdInDays | Should -Be 45
                    $warnModel | Should -BeNullOrEmpty
                } finally {
                    $null = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceMulti1 -Database model -StaleQueryThreshold $originalThreshold
                }
            } else {
                $resultsModel = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceMulti1 -Database model -StaleQueryThreshold 45 -WarningVariable warnModel
                $resultsModel | Should -BeNullOrEmpty
                $warnModel -join "`n" | Should -Match "Query Store cannot be read on model before SQL Server 2022"
            }
        }
    }
}