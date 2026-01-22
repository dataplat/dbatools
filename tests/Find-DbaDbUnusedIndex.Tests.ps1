#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaDbUnusedIndex",
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
                "IgnoreUptime",
                "Seeks",
                "Scans",
                "Lookups",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output Validation" {
        BeforeAll {
            Test-DbaConnection -SqlInstance $TestConfig.InstanceSingle

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

            $random = Get-Random
            $dbName = "dbatoolsci_$random"

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName
            $newDB = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName

            $indexName = "dbatoolsci_index_$random"
            $tableName = "dbatoolsci_table_$random"
            $sql = "USE $dbName;
                    CREATE TABLE $tableName (ID INTEGER);
                    CREATE INDEX $indexName ON $tableName (ID);
                    INSERT INTO $tableName (ID) VALUES (1);
                    SELECT ID FROM $tableName;
                    WAITFOR DELAY '00:00:05'; -- for slower systems allow the query optimizer engine to catch up and update sys.dm_db_index_usage_stats"

            $null = $server.Query($sql)

            $result = Find-DbaDbUnusedIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbName -IgnoreUptime -Seeks 10 -Scans 10 -Lookups 10 -EnableException
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "DatabaseId",
                "Schema",
                "Table",
                "ObjectId",
                "IndexName",
                "IndexId",
                "TypeDesc",
                "UserSeeks",
                "UserScans",
                "UserLookups",
                "UserUpdates",
                "LastUserSeek",
                "LastUserScan",
                "LastUserLookup",
                "LastUserUpdate",
                "SystemSeeks",
                "SystemScans",
                "SystemLookup",
                "SystemUpdates",
                "LastSystemSeek",
                "LastSystemScan",
                "LastSystemLookup",
                "LastSystemUpdate",
                "IndexSizeMB",
                "RowCount"
            )

            # CompressionDescription only on SQL 2008+
            if ($server.VersionMajor -gt 9) {
                $expectedProps += "CompressionDescription"
            }

            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }

    Context "Verify basics of the Find-DbaDbUnusedIndex command" {
        BeforeAll {
            Test-DbaConnection -SqlInstance $TestConfig.InstanceSingle

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

            $random = Get-Random
            $dbName = "dbatoolsci_$random"

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName
            $newDB = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName

            $indexName = "dbatoolsci_index_$random"
            $tableName = "dbatoolsci_table_$random"
            $sql = "USE $dbName;
                    CREATE TABLE $tableName (ID INTEGER);
                    CREATE INDEX $indexName ON $tableName (ID);
                    INSERT INTO $tableName (ID) VALUES (1);
                    SELECT ID FROM $tableName;
                    WAITFOR DELAY '00:00:05'; -- for slower systems allow the query optimizer engine to catch up and update sys.dm_db_index_usage_stats"

            $null = $server.Query($sql)
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        }

        It "Should find the 'unused' index on each test sql instance" {
            $results = Find-DbaDbUnusedIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbName -IgnoreUptime -Seeks 10 -Scans 10 -Lookups 10
            $results.Database | Should -Be $dbName
            $results.DatabaseId | Should -Be $newDB.Id

            $testSQLinstance = $false

            foreach ($row in $results) {
                if ($row["IndexName"] -eq $indexName) {
                    $testSQLinstance = $true
                }
            }

            $testSQLinstance | Should -Be $true
        }


        It "Should return the expected columns on each test sql instance" {
            $expectedColumnArray = @(
                "CompressionDescription",
                "ComputerName",
                "Database",
                "DatabaseId",
                "IndexId",
                "IndexName",
                "IndexSizeMB",
                "InstanceName",
                "LastSystemLookup",
                "LastSystemScan",
                "LastSystemSeek",
                "LastSystemUpdate",
                "LastUserLookup",
                "LastUserScan",
                "LastUserSeek",
                "LastUserUpdate",
                "ObjectId",
                "RowCount",
                "Schema",
                "SqlInstance",
                "SystemLookup",
                "SystemScans",
                "SystemSeeks",
                "SystemUpdates",
                "Table",
                "TypeDesc",
                "UserLookups",
                "UserScans",
                "UserSeeks",
                "UserUpdates"
            )

            $testSQLinstance = $false

            $results = Find-DbaDbUnusedIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbName -IgnoreUptime -Seeks 10 -Scans 10 -Lookups 10

            if ( ($null -ne $results) ) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    $testSQLinstance = $false
                }

                if ($null -ne $row) {
                    $columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $PSItem.Name })

                    if ( @(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0 ) {
                        $testSQLinstance = $true
                    }
                }
            }

            $testSQLinstance | Should -Be $true
        }
    }
}