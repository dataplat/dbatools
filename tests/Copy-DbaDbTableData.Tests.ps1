#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaDbTableData",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeDiscovery {
    # Azure SQL Database supports GENERATED ALWAYS columns while its product version says 12, so it is the
    # one destination where a version check alone gets the writable columns wrong. No CI environment has
    # one; a lab configuration supplies it through AzureSqlDbServer and everywhere else the test skips
    # itself. The value decides a Skip, so it has to exist at discovery time.
    $script:hasAzureSqlDb = -not [string]::IsNullOrWhiteSpace($TestConfig.AzureSqlDbServer)
}

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Database",
                "DestinationDatabase",
                "Table",
                "View",
                "Query",
                "ForceExplicitMapping",
                "AutoCreateTable",
                "BatchSize",
                "NotifyAfter",
                "DestinationTable",
                "NoTableLock",
                "CheckConstraints",
                "FireTriggers",
                "KeepIdentity",
                "KeepNulls",
                "Truncate",
                "BulkCopyTimeout",
                "CommandTimeout",
                "UseDefaultFileGroup",
                "ScriptingOptionsObject",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb
        $destinationDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example (id int);
            INSERT dbo.dbatoolsci_example
            SELECT top 10 1
            FROM sys.objects")
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example2 (id int)")
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 1
            FROM sys.objects")
        $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_example (id int)")
        $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
        $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 2
            FROM sys.objects")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example")
        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example2")
        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example3")
        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example4")
        $null = $destinationDb.Query("DROP TABLE dbo.dbatoolsci_example3")
        $null = $destinationDb.Query("DROP TABLE dbo.dbatoolsci_example4")
        $null = $destinationDb.Query("DROP TABLE dbo.dbatoolsci_example")
        $null = $sourceDb.Query("DROP TABLE tempdb.dbo.dbatoolsci_willexist")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying table data within same instance" {
        It "copies the table data" {
            $results = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example2
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $sourceDb.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
            $results.SourceDatabaseID | Should -Be $sourceDb.ID
            $results.DestinationDatabaseID | Should -Be $sourceDb.ID
        }
    }

    Context "When copying table data between instances" {
        It "copies the table data to another instance" {
            $null = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Database tempdb -Table tempdb.dbo.dbatoolsci_example -DestinationTable dbatoolsci_example3
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $destinationDb.Query("select id from dbo.dbatoolsci_example3")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "Copy data using a query that relies on the default source database" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) id FROM dbo.dbatoolsci_example4 ORDER BY id DESC" -DestinationTable dbatoolsci_example3 -Truncate
            $result.RowsCopied | Should -Be 1
        }

        It "Copy data using a query that uses a 3 part query" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) id FROM tempdb.dbo.dbatoolsci_example4 ORDER BY id DESC" -DestinationTable dbatoolsci_example3 -Truncate
            $result.RowsCopied | Should -Be 1
        }

        It "Points at the Query requirement when Query is used without a source table" {
            # The generic message reads as if SqlInstance or Database were missing (#10676).
            $splatQueryOnly = @{
                SqlInstance      = $TestConfig.InstanceCopy2
                Database         = "tempdb"
                Query            = "SELECT TOP (1) Id FROM dbo.dbatoolsci_example4"
                DestinationTable = "dbatoolsci_example3"
                WarningAction    = "SilentlyContinue"
            }
            $result = Copy-DbaDbTableData @splatQueryOnly
            $result | Should -BeNullOrEmpty
            $WarnVar | Should -Match "When using Query"
        }
    }

    Context "When testing pipeline functionality" {
        It "supports piping" {
            $null = Get-DbaDbTable -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example2 -Truncate
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $sourceDb.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "supports piping more than one table" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example2, dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example3
            $results.Count | Should -Be 2
            $results.RowsCopied | Measure-Object -Sum | Select-Object -ExpandProperty Sum | Should -Be 20
        }

        It "opens and closes connections properly" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table "dbo.dbatoolsci_example", "dbo.dbatoolsci_example4" | Copy-DbaDbTableData -Destination $TestConfig.InstanceCopy2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
            $results.Count | Should -Be 2
            $table1DbCount = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table4DbCount = $destinationDb.Query("select id from dbo.dbatoolsci_example4")
            $table1Db2Count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table4Db2Count = $destinationDb.Query("select id from dbo.dbatoolsci_example4")
            $table1DbCount.Count | Should -Be $table1Db2Count.Count
            $table4DbCount.Count | Should -Be $table4Db2Count.Count
            $results[0].RowsCopied | Should -Be 10
            $results[1].RowsCopied | Should -Be 13
            $table4Db2Check = $destinationDb.Query("select id from dbo.dbatoolsci_example4 where id = 1")
            $table4Db2Check.Count | Should -Be 13
        }
    }

    Context "When handling edge cases" {
        It "Should return nothing if Source and Destination are same" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -Truncate -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -Be $null
            $warn | Should -Match "Cannot copy .* into itself"
        }

        It "Should warn if the destinaton table doesn't exist" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning 3> $null
            $result | Should -Be $null
            $tablewarning | Should -Match Auto
        }

        It "automatically creates the table" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_willexist -AutoCreateTable
            $result.DestinationTable | Should -Be "dbatoolsci_willexist"
        }
    }

    Context "When destination table has computed columns" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_computed_source (Dt DATETIME)")
            $null = $sourceDb.Query("INSERT dbo.dbatoolsci_computed_source (Dt) VALUES (GETDATE()), (DATEADD(MONTH, -1, GETDATE()))")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_computed_dest (Dt DATETIME, DtDay AS (DATEPART(DAY, Dt)), DtMonth AS (DATEPART(MONTH, Dt)), DtYear AS (DATEPART(YEAR, Dt)))")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_computed_source', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_computed_source")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_computed_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_computed_dest")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy data successfully when destination has computed columns" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Database tempdb -Table dbatoolsci_computed_source -DestinationTable dbatoolsci_computed_dest
            $result.RowsCopied | Should -Be 2
            $destCount = $destinationDb.Query("SELECT * FROM dbo.dbatoolsci_computed_dest")
            $destCount.Count | Should -Be 2
        }

        It "Should copy data using Query with ForceExplicitMapping when destination has computed columns" {
            # First truncate dest table
            $null = $destinationDb.Query("TRUNCATE TABLE dbo.dbatoolsci_computed_dest")

            # Use Query parameter with ForceExplicitMapping to enable name-based column mapping
            # This is needed when using Query with tables that have computed columns
            $splatCopy = @{
                SqlInstance          = $TestConfig.InstanceCopy1
                Destination          = $TestConfig.InstanceCopy2
                Database             = "tempdb"
                Table                = "dbatoolsci_computed_source"
                Query                = "SELECT Dt FROM dbo.dbatoolsci_computed_source"
                DestinationTable     = "dbatoolsci_computed_dest"
                ForceExplicitMapping = $true
            }
            $result = Copy-DbaDbTableData @splatCopy
            $result.RowsCopied | Should -Be 2
            $destCount = $destinationDb.Query("SELECT * FROM dbo.dbatoolsci_computed_dest")
            $destCount.Count | Should -Be 2
        }
    }

    Context "When using Query without ForceExplicitMapping and the destination has unwritable columns" {
        BeforeDiscovery {
            # GENERATED ALWAYS columns arrived with SQL Server 2016 and exist on Azure SQL Database, so the
            # temporal scenario below cannot be built anywhere else. The value decides a Skip, which Pester
            # needs while it discovers the tests, so it cannot be read in BeforeAll.
            $discoveryDestServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $destSupportsTemporal = $discoveryDestServer.VersionMajor -ge 13 -or $discoveryDestServer.DatabaseEngineType -eq "SqlAzureDatabase"
        }

        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_positional_source (Id INT, A INT, B INT, C INT)")
            $null = $sourceDb.Query("INSERT dbo.dbatoolsci_positional_source (Id, A, B, C) VALUES (1, 11, 22, 33), (2, 111, 222, 333)")
            # A computed and a rowversion column sit between the writable ones, so a positional mapping that
            # counts them shifts every column behind them (#10661).
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_positional_dest (Id INT, A INT, Computed AS (A * 10), RV ROWVERSION, B INT, C INT)")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_positional_identity (Id INT IDENTITY(1, 1), A INT, B INT, C INT)")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_positional_rowversion (Id INT, A INT, RV ROWVERSION, B INT, C INT)")
            if ($destinationDb.Parent.VersionMajor -ge 13 -or $destinationDb.Parent.DatabaseEngineType -eq "SqlAzureDatabase") {
                # The period columns of a temporal table are GENERATED ALWAYS: not computed, not rowversion,
                # but just as unwritable, and interleaved with the writable columns here on purpose.
                $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_positional_temporal (Id INT PRIMARY KEY, A INT, ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL, B INT, ValidTo DATETIME2 GENERATED ALWAYS AS ROW END NOT NULL, C INT, PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.dbatoolsci_positional_temporal_history))")
            }

            $splatPositional = @{
                SqlInstance      = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = "tempdb"
                Table            = "dbatoolsci_positional_source"
                Query            = "SELECT Id, A, B, C FROM dbo.dbatoolsci_positional_source"
                DestinationTable = "dbatoolsci_positional_dest"
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("DROP TABLE IF EXISTS dbo.dbatoolsci_positional_source")
            $null = $destinationDb.Query("DROP TABLE IF EXISTS dbo.dbatoolsci_positional_dest")
            $null = $destinationDb.Query("DROP TABLE IF EXISTS dbo.dbatoolsci_positional_identity")
            $null = $destinationDb.Query("DROP TABLE IF EXISTS dbo.dbatoolsci_positional_rowversion")
            $destinationDb.Tables.Refresh()
            if ($destinationDb.Tables | Where-Object Name -eq "dbatoolsci_positional_temporal") {
                # System versioning has to be turned off before the temporal table can be dropped.
                $null = $destinationDb.Query("ALTER TABLE dbo.dbatoolsci_positional_temporal SET (SYSTEM_VERSIONING = OFF)")
                $null = $destinationDb.Query("DROP TABLE dbo.dbatoolsci_positional_temporal")
                $null = $destinationDb.Query("DROP TABLE IF EXISTS dbo.dbatoolsci_positional_temporal_history")
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Maps the query columns by position onto the writable destination columns only" {
            $result = Copy-DbaDbTableData @splatPositional
            $WarnVar | Should -BeNullOrEmpty
            $result.RowsCopied | Should -Be 2

            $destData = $destinationDb.Query("SELECT Id, A, Computed, B, C FROM dbo.dbatoolsci_positional_dest ORDER BY Id")
            $destData.A | Should -Be @(11, 111)
            $destData.Computed | Should -Be @(110, 1110)
            $destData.B | Should -Be @(22, 222)
            $destData.C | Should -Be @(33, 333)
        }

        It "Does not shift the columns behind a rowversion column" {
            # This is the silent variant: SqlBulkCopy drops the source column that lands on the rowversion
            # column and reports success, so the last column ends up empty and the ones before it are off by one.
            $splatRowversion = $splatPositional.Clone()
            $splatRowversion.DestinationTable = "dbatoolsci_positional_rowversion"
            $result = Copy-DbaDbTableData @splatRowversion
            $WarnVar | Should -BeNullOrEmpty
            $result.RowsCopied | Should -Be 2

            $destData = $destinationDb.Query("SELECT Id, A, B, C FROM dbo.dbatoolsci_positional_rowversion ORDER BY Id")
            $destData.B | Should -Be @(22, 222)
            $destData.C | Should -Be @(33, 333)
        }

        It "Does not count the generated always columns of a temporal destination" -Skip:(-not $destSupportsTemporal) {
            # The period columns are GENERATED ALWAYS, so the server refuses explicit values for them.
            # A positional mapping that counts them maps writable source columns onto them and fails.
            $splatTemporal = $splatPositional.Clone()
            $splatTemporal.DestinationTable = "dbatoolsci_positional_temporal"
            $result = Copy-DbaDbTableData @splatTemporal
            $WarnVar | Should -BeNullOrEmpty
            $result.RowsCopied | Should -Be 2

            $destData = $destinationDb.Query("SELECT Id, A, ValidFrom, B, ValidTo, C FROM dbo.dbatoolsci_positional_temporal ORDER BY Id")
            $destData.A | Should -Be @(11, 111)
            $destData.B | Should -Be @(22, 222)
            $destData.C | Should -Be @(33, 333)
            $destData.ValidFrom | Should -Not -BeNullOrEmpty
        }

        It "Still ignores the identity placeholder unless KeepIdentity is used" {
            $splatIdentity = $splatPositional.Clone()
            $splatIdentity.Query = "SELECT 0, A, B, C FROM dbo.dbatoolsci_positional_source ORDER BY Id"
            $splatIdentity.DestinationTable = "dbatoolsci_positional_identity"
            $result = Copy-DbaDbTableData @splatIdentity
            $WarnVar | Should -BeNullOrEmpty
            $result.RowsCopied | Should -Be 2

            $destData = $destinationDb.Query("SELECT Id, A, B, C FROM dbo.dbatoolsci_positional_identity ORDER BY Id")
            $destData.Id | Should -Be @(1, 2)
            $destData.A | Should -Be @(11, 111)
            $destData.C | Should -Be @(33, 333)
        }

        It "Refuses a query with more columns than the destination can take instead of dropping them" {
            $splatTooMany = $splatPositional.Clone()
            $splatTooMany.Query = "SELECT Id, A, B, C, C AS Extra FROM dbo.dbatoolsci_positional_source"
            $splatTooMany.Truncate = $true
            $result = Copy-DbaDbTableData @splatTooMany -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $WarnVar | Should -Match "5 columns"
            $WarnVar | Should -Match "4 writable columns"
            $destinationDb.Query("SELECT COUNT(*) AS RowCnt FROM dbo.dbatoolsci_positional_dest").RowCnt | Should -Be 0
        }
    }

    Context "When using Query against a temporal destination on Azure SQL Database" -Skip:(-not $script:hasAzureSqlDb) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Azure SQL Database reports product version 12.0 and still has GENERATED ALWAYS columns, so
            # the writable columns of a temporal destination cannot be decided by the version alone there.
            # A serverless database that has been idle is paused and takes up to a minute to wake up. A
            # generous ConnectTimeout does not cover that: while the database resumes, Azure does not
            # keep the attempt waiting, it answers it right away with error 40613 "Database ... is not
            # currently available. Please retry the connection later." So the first connection is
            # retried until the database is up, and only an error that says something else is thrown
            # immediately.
            $splatAzureConnect = @{
                SqlInstance    = $TestConfig.AzureSqlDbServer
                Database       = $TestConfig.AzureSqlDbName
                SqlCredential  = $TestConfig.AzureSqlDbCred
                ConnectTimeout = 120
            }
            $azureResumeAttempt = 0
            while ($null -eq $serverAzure) {
                $azureResumeAttempt++
                try {
                    $serverAzure = Connect-DbaInstance @splatAzureConnect
                } catch {
                    if ($azureResumeAttempt -ge 10 -or $PSItem.Exception.Message -notmatch "is not currently available") {
                        throw
                    }
                    Start-Sleep -Seconds 15
                }
            }
            $azureDb = $serverAzure.Databases[$TestConfig.AzureSqlDbName]

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_azure_source (Id INT, A INT, B INT, C INT)")
            $null = $sourceDb.Query("INSERT dbo.dbatoolsci_azure_source (Id, A, B, C) VALUES (1, 11, 22, 33), (2, 111, 222, 333)")
            # The same interleaved layout as the temporal test above, on the engine whose version cannot decide it.
            $null = $azureDb.Query("CREATE TABLE dbo.dbatoolsci_azure_temporal (Id INT PRIMARY KEY, A INT, ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL, B INT, ValidTo DATETIME2 GENERATED ALWAYS AS ROW END NOT NULL, C INT, PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.dbatoolsci_azure_temporal_history))")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("DROP TABLE IF EXISTS dbo.dbatoolsci_azure_source")
            # The BeforeAll can fail partway through - an Azure SQL Database that stays unavailable is the
            # realistic case - and then the database object below was never assigned.
            if ($azureDb) {
                $azureDb.Tables.Refresh()
                if ($azureDb.Tables | Where-Object Name -eq "dbatoolsci_azure_temporal") {
                    # System versioning has to be turned off before the temporal table can be dropped.
                    $null = $azureDb.Query("ALTER TABLE dbo.dbatoolsci_azure_temporal SET (SYSTEM_VERSIONING = OFF)")
                    $null = $azureDb.Query("DROP TABLE dbo.dbatoolsci_azure_temporal")
                    $null = $azureDb.Query("DROP TABLE IF EXISTS dbo.dbatoolsci_azure_temporal_history")
                }
            }
            if ($serverAzure) {
                $null = $serverAzure | Disconnect-DbaInstance
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "really is an Azure SQL Database, which is what makes this case different" {
            # Guards the test below: against a SQL Server 2016 or later it would pass without proving
            # anything, because there the version check alone already excludes the period columns.
            $serverAzure.DatabaseEngineEdition | Should -Be "SqlDatabase"
            $serverAzure.Version.Major | Should -Be 12
        }

        It "Does not count the generated always columns of a temporal destination on Azure SQL Database" {
            $splatAzureCopy = @{
                SqlInstance              = $TestConfig.InstanceCopy1
                Database                 = "tempdb"
                Table                    = "dbatoolsci_azure_source"
                Query                    = "SELECT Id, A, B, C FROM dbo.dbatoolsci_azure_source"
                Destination              = $TestConfig.AzureSqlDbServer
                DestinationSqlCredential = $TestConfig.AzureSqlDbCred
                DestinationDatabase      = $TestConfig.AzureSqlDbName
                DestinationTable         = "dbatoolsci_azure_temporal"
            }
            $result = Copy-DbaDbTableData @splatAzureCopy
            $WarnVar | Should -BeNullOrEmpty
            $result.RowsCopied | Should -Be 2

            $destData = $azureDb.Query("SELECT Id, A, ValidFrom, B, ValidTo, C FROM dbo.dbatoolsci_azure_temporal ORDER BY Id")
            $destData.A | Should -Be @(11, 111)
            $destData.B | Should -Be @(22, 222)
            $destData.C | Should -Be @(33, 333)
            $destData.ValidFrom | Should -Not -BeNullOrEmpty
        }
    }

    Context "Regression tests" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_ordering_test (id INT IDENTITY(1,1) PRIMARY KEY, data_hash VARBINARY(32))")
            $null = $sourceDb.Query("INSERT INTO dbo.dbatoolsci_ordering_test (data_hash) VALUES (0x0102030405), (0x0607080910), (0x1112131415)")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_ordering_test', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_ordering_test")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_ordering_test_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_ordering_test_dest")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should maintain correct row order when copying tables with varbinary fields (issue #9610)" {
            $splatCopy = @{
                SqlInstance      = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = "tempdb"
                Table            = "dbatoolsci_ordering_test"
                DestinationTable = "dbatoolsci_ordering_test_dest"
                AutoCreateTable  = $true
            }
            $result = Copy-DbaDbTableData @splatCopy
            $result.RowsCopied | Should -Be 3

            $sourceData = $sourceDb.Query("SELECT id, data_hash FROM dbo.dbatoolsci_ordering_test ORDER BY id")
            $destData = $destinationDb.Query("SELECT id, data_hash FROM dbo.dbatoolsci_ordering_test_dest ORDER BY id")

            for ($i = 0; $i -lt $sourceData.Count; $i++) {
                $sourceData[$i].id | Should -Be $destData[$i].id
                $sourceData[$i].data_hash | Should -Be $destData[$i].data_hash
            }
        }
    }

    Context "When the bulk copy fails" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_leak_source (id INT); INSERT dbo.dbatoolsci_leak_source (id) VALUES (1), (2), (3)")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_leak_dest (id INT)")

            # The bulk copy fails on the first row, because the string cannot be converted to the INT column of the
            # destination. The cross joins make sure that the source has far more rows to send than the client has
            # read by then, so the SELECT is still running when the copy fails (#10685). The marker in the SELECT
            # finds the request afterwards, its own session is excluded because the text of the check contains it too.
            $leakQuery = "SELECT 'dbatoolsci_leak_marker' AS id FROM dbo.dbatoolsci_leak_source AS s CROSS JOIN sys.all_objects AS a CROSS JOIN sys.all_objects AS b"
            $leakRequestQuery = "SELECT r.session_id FROM sys.dm_exec_requests AS r CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t WHERE t.text LIKE '%dbatoolsci_leak_marker%' AND r.session_id <> @@SPID"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A leaked request holds a lock on the source table, so the DROP TABLE would wait for it forever.
            foreach ($leakedRequest in $sourceDb.Query($leakRequestQuery)) {
                $null = $sourceDb.Query("KILL $($leakedRequest.session_id)")
            }
            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_leak_source', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_leak_source")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_leak_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_leak_dest")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Stops the SELECT on the source when writing to the destination fails" {
            $splatFailingCopy = @{
                SqlInstance      = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = "tempdb"
                Table            = "dbatoolsci_leak_source"
                Query            = $leakQuery
                DestinationTable = "dbatoolsci_leak_dest"
                WarningAction    = "SilentlyContinue"
            }
            $result = Copy-DbaDbTableData @splatFailingCopy
            $result | Should -BeNullOrEmpty
            $WarnVar | Should -Match "Something went wrong"

            $leakedRequests = @($sourceDb.Query($leakRequestQuery))
            $leakedRequests.Count | Should -Be 0
            # The lock of a leaked request is what blocked the DDL on the source table for the reporter.
            { $sourceDb.Query("SET LOCK_TIMEOUT 5000; ALTER TABLE dbo.dbatoolsci_leak_source ADD extra INT") } | Should -Not -Throw
        }
    }
}
