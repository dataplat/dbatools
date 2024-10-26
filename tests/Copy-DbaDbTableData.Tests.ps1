#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Copy-DbaDbTableData" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Copy-DbaDbTableData
            $expected = $TestConfig.CommonParameters
            $expected += @(
                'SqlInstance',
                'SqlCredential',
                'Destination', 
                'DestinationSqlCredential',
                'Database',
                'DestinationDatabase',
                'Table',
                'View',
                'Query',
                'AutoCreateTable',
                'BatchSize',
                'NotifyAfter',
                'DestinationTable',
                'NoTableLock',
                'CheckConstraints',
                'FireTriggers',
                'KeepIdentity',
                'KeepNulls',
                'Truncate',
                'BulkCopyTimeout',
                'CommandTimeout',
                'UseDefaultFileGroup',
                'InputObject',
                'EnableException',
                'Confirm',
                'WhatIf'
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Copy-DbaDbTableData" -Tag "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempdb
        $db2 = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database tempdb
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example (id int);
            INSERT dbo.dbatoolsci_example
            SELECT top 10 1
            FROM sys.objects")
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example2 (id int)")
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 1
            FROM sys.objects")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_example (id int)")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 2
            FROM sys.objects")
    }

    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.dbatoolsci_example")
            $null = $db.Query("DROP TABLE dbo.dbatoolsci_example2")
            $null = $db.Query("DROP TABLE dbo.dbatoolsci_example3")
            $null = $db.Query("DROP TABLE dbo.dbatoolsci_example4")
            $null = $db2.Query("DROP TABLE dbo.dbatoolsci_example3")
            $null = $db2.Query("DROP TABLE dbo.dbatoolsci_example4")
            $null = $db2.Query("DROP TABLE dbo.dbatoolsci_example")
            $null = $db.Query("DROP TABLE tempdb.dbo.dbatoolsci_willexist")
        } catch {
            $null = 1
        }
    }

    Context "When copying table data within same instance" {
        It "copies the table data" {
            $results = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example2
            $table1count = $db.Query("select id from dbo.dbatoolsci_example")
            $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
            $results.SourceDatabaseID | Should -Be $db.ID
            $results.DestinationDatabaseID | Should -Be $db.ID
        }
    }

    Context "When copying table data between instances" {
        It "copies the table data to another instance" {
            $null = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Destination $TestConfig.instance2 -Database tempdb -Table tempdb.dbo.dbatoolsci_example -DestinationTable dbatoolsci_example3
            $table1count = $db.Query("select id from dbo.dbatoolsci_example")
            $table2count = $db2.Query("select id from dbo.dbatoolsci_example3")
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
            $table1count = $db.Query("select id from dbo.dbatoolsci_example")
            $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "supports piping more than one table" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example2, dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example3
            $results.Count | Should -Be 2
            $results.RowsCopied | Measure-Object -Sum | Select-Object -Expand Sum | Should -Be 20
        }

        It "opens and closes connections properly" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database tempdb -Table 'dbo.dbatoolsci_example', 'dbo.dbatoolsci_example4' | Copy-DbaDbTableData -Destination $TestConfig.instance2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
            $results.Count | Should -Be 2
            $table1DbCount = $db.Query("select id from dbo.dbatoolsci_example")
            $table4DbCount = $db2.Query("select id from dbo.dbatoolsci_example4")
            $table1Db2Count = $db.Query("select id from dbo.dbatoolsci_example")
            $table4Db2Count = $db2.Query("select id from dbo.dbatoolsci_example4")
            $table1DbCount.Count | Should -Be $table1Db2Count.Count
            $table4DbCount.Count | Should -Be $table4Db2Count.Count
            $results[0].RowsCopied | Should -Be 10
            $results[1].RowsCopied | Should -Be 13
            $table4Db2Check = $db2.Query("select id from dbo.dbatoolsci_example4 where id = 1")
            $table4Db2Check.Count | Should -Be 13
        }
    }

    Context "When handling edge cases" {
        It "Should return nothing if Source and Destination are same" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example -Truncate
            $result | Should -Be $null
        }

        It "Should warn if the destinaton table doesn't exist" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning 3> $null
            $result | Should -Be $null
            $tablewarning | Should -Match Auto
        }

        It "automatically creates the table" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_willexist -AutoCreateTable
            $result.DestinationTable | Should -Be 'dbatoolsci_willexist'
        }

        It "Should warn if the source database doesn't exist" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.instance2 -Database tempdb_invalid -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning 3> $null
            $result | Should -Be $null
            $tablewarning | Should -Match "cannot open database"
        }
    }
}
