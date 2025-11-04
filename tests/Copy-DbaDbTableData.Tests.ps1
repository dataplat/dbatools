#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDbTableData",
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
                "Destination",
                "DestinationSqlCredential",
                "Database",
                "DestinationDatabase",
                "Table",
                "View",
                "Query",
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

        $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempdb
        $destinationDb = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database tempdb
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
            $results = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example2
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $sourceDb.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
            $results.SourceDatabaseID | Should -Be $sourceDb.ID
            $results.DestinationDatabaseID | Should -Be $sourceDb.ID
        }
    }

    Context "When copying table data between instances" {
        It "copies the table data to another instance" {
            $null = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Destination $TestConfig.instance2 -Database tempdb -Table tempdb.dbo.dbatoolsci_example -DestinationTable dbatoolsci_example3
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $destinationDb.Query("select id from dbo.dbatoolsci_example3")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "Copy data using a query that relies on the default source database" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) Id FROM dbo.dbatoolsci_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
            $result.RowsCopied | Should -Be 1
        }

        It "Copy data using a query that uses a 3 part query" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) Id FROM tempdb.dbo.dbatoolsci_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
            $result.RowsCopied | Should -Be 1
        }
    }

    Context "When testing pipeline functionality" {
        It "supports piping" {
            $null = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example2 -Truncate
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $sourceDb.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "supports piping more than one table" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example2, dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example3
            $results.Count | Should -Be 2
            $results.RowsCopied | Measure-Object -Sum | Select-Object -ExpandProperty Sum | Should -Be 20
        }

        It "opens and closes connections properly" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database tempdb -Table "dbo.dbatoolsci_example", "dbo.dbatoolsci_example4" | Copy-DbaDbTableData -Destination $TestConfig.instance2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
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
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example -Truncate -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -Be $null
            $warn | Should -Match "Cannot copy .* into itself"
        }

        It "Should warn if the destinaton table doesn't exist" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning 3> $null
            $result | Should -Be $null
            $tablewarning | Should -Match Auto
        }

        It "automatically creates the table" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_willexist -AutoCreateTable
            $result.DestinationTable | Should -Be "dbatoolsci_willexist"
        }

        It "Should warn if the source database doesn't exist" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance2 -Database tempdb_invalid -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning 3> $null
            $result | Should -Be $null
            $tablewarning | Should -Match "cannot open database"
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

            $null = $sourceDb.Query("DROP TABLE IF EXISTS dbo.dbatoolsci_computed_source")
            $null = $destinationDb.Query("DROP TABLE IF EXISTS dbo.dbatoolsci_computed_dest")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy data successfully when destination has computed columns" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Destination $TestConfig.instance2 -Database tempdb -Table dbatoolsci_computed_source -DestinationTable dbatoolsci_computed_dest
            $result.RowsCopied | Should -Be 2
            $destCount = $destinationDb.Query("SELECT * FROM dbo.dbatoolsci_computed_dest")
            $destCount.Count | Should -Be 2
        }
    }
}