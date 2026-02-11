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

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputRandom = Get-Random
            $outputDbName = "dbatoolsci_output_$outputRandom"
            $outputTableName = "dbatoolsci_table_$outputRandom"
            $outputIndexName = "dbatoolsci_index_$outputRandom"

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $outputDbName

            $outputServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $outputSql = "USE $outputDbName;
                    CREATE TABLE $outputTableName (ID INTEGER);
                    CREATE INDEX $outputIndexName ON $outputTableName (ID);
                    INSERT INTO $outputTableName (ID) VALUES (1);
                    SELECT ID FROM $outputTableName;
                    WAITFOR DELAY '00:00:05';"
            $null = $outputServer.Query($outputSql)

            $result = @(Find-DbaDbUnusedIndex -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -IgnoreUptime -Seeks 10 -Scans 10 -Lookups 10)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [System.Data.DataRow]
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
                "IndexSizeMB",
                "RowCount"
            )
            $propNames = @($result[0] | Get-Member -MemberType Property | ForEach-Object { $PSItem.Name })
            foreach ($prop in $expectedProps) {
                $propNames | Should -Contain $prop -Because "property '$prop' should be present in the output"
            }
        }
    }
}