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

    Context "Never used indexes, inaccessible databases and the uptime of the instance" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $random = Get-Random
            $unusedDbName = "dbatoolsci_unused_$random"
            $offlineDbName = "dbatoolsci_unusedoffline_$random"
            $untouchedIndexName = "dbatoolsci_untouched_$random"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $unusedDbName, $offlineDbName
            # The index is never read or written, so it gets no row in sys.dm_db_index_usage_stats
            $splatUntouchedIndex = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $unusedDbName
                Query       = "CREATE TABLE dbo.dbatoolsci_untouched (ID int); CREATE INDEX $untouchedIndexName ON dbo.dbatoolsci_untouched (ID);"
            }
            $null = Invoke-DbaQuery @splatUntouchedIndex
            $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName -Offline -Force

            # tempdb (database_id 2) is created at every start. The uptime decides whether the command refuses to evaluate.
            $uptimeRow = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "SELECT create_date AS CreateDate, GETDATE() AS ServerTime FROM sys.databases WHERE database_id = 2"
            $recentlyRestarted = (New-TimeSpan -Start $uptimeRow.CreateDate -End $uptimeRow.ServerTime).Days -le 6

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Online again first, so that dropping the database also deletes its files
            $null = Set-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName -Online -Force -ErrorAction SilentlyContinue
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $unusedDbName, $offlineDbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Finds an index that was not used at all since the start of the instance" {
            $results = Find-DbaDbUnusedIndex -SqlInstance $TestConfig.InstanceSingle -Database $unusedDbName -IgnoreUptime
            $WarnVar | Should -BeNullOrEmpty
            $untouchedIndex = $results | Where-Object IndexName -eq $untouchedIndexName
            @($untouchedIndex).Count | Should -Be 1
            $untouchedIndex.UserSeeks | Should -Be 0
            $untouchedIndex.UserScans | Should -Be 0
            $untouchedIndex.UserLookups | Should -Be 0
        }

        It "Skips a database that is not accessible and goes on with the next one" {
            $results = Find-DbaDbUnusedIndex -SqlInstance $TestConfig.InstanceSingle -Database $offlineDbName, $unusedDbName -IgnoreUptime -WarningAction SilentlyContinue
            @($WarnVar).Count | Should -Be 1
            $WarnVar | Should -BeLike "*$offlineDbName*is not accessible*"
            $results.IndexName | Should -Contain $untouchedIndexName
        }

        It "Returns to its caller when no database is found" {
            # Issue #10806: a continue without a loop of its own skipped the rest of the loop of the caller
            $iterations = 0
            foreach ($attempt in 1..2) {
                $null = Find-DbaDbUnusedIndex -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_nosuchdb_$random" -IgnoreUptime -WarningAction SilentlyContinue
                $iterations++
            }
            $iterations | Should -Be 2
            $WarnVar | Should -BeLike "*was not found*"
        }

        It "Measures the uptime on the clock of the instance when this computer is ahead of it" {
            # Issue #10833: a test computer shares the clock of its instance, so only the clock of this computer is moved,
            # the instance stays real. An uptime measured on this clock would always look long enough.
            # Which outcome is right depends on how long ago the instance really started, so the test asks the instance.
            Mock -ModuleName dbatools -CommandName Get-Date -ParameterFilter { $PesterBoundParameters.Count -eq 0 } -MockWith { [datetime]::Now.AddDays(30) }
            $results = Find-DbaDbUnusedIndex -SqlInstance $TestConfig.InstanceSingle -Database $unusedDbName -WarningAction SilentlyContinue
            if ($recentlyRestarted) {
                $WarnVar | Should -BeLike "*not long enough for a solid evaluation*"
                $results | Should -BeNullOrEmpty
            } else {
                $WarnVar | Should -BeNullOrEmpty
                $results.IndexName | Should -Contain $untouchedIndexName
            }
        }

        It "Measures the uptime on the clock of the instance when this computer is behind it" {
            # The other direction: an uptime measured on this clock would always look too short.
            Mock -ModuleName dbatools -CommandName Get-Date -ParameterFilter { $PesterBoundParameters.Count -eq 0 } -MockWith { [datetime]::Now.AddDays(-30) }
            $results = Find-DbaDbUnusedIndex -SqlInstance $TestConfig.InstanceSingle -Database $unusedDbName -WarningAction SilentlyContinue
            if ($recentlyRestarted) {
                $WarnVar | Should -BeLike "*not long enough for a solid evaluation*"
                $results | Should -BeNullOrEmpty
            } else {
                $WarnVar | Should -BeNullOrEmpty
                $results.IndexName | Should -Contain $untouchedIndexName
            }
        }
    }
}