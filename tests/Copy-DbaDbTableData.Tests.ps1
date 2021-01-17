$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'AutoCreateTable', 'BatchSize', 'bulkCopyTimeOut', 'CheckConstraints', 'Database', 'Destination', 'DestinationDatabase', 'DestinationSqlCredential', 'DestinationTable', 'EnableException', 'FireTriggers', 'InputObject', 'KeepIdentity', 'KeepNulls', 'NoTableLock', 'NotifyAfter', 'Query', 'SqlCredential', 'SqlInstance', 'Table', 'Truncate', 'View'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        $db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database tempdb
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

    It "copies the table data" {
        $null = Copy-DbaDbTableData -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example2
        $table1count = $db.Query("select id from dbo.dbatoolsci_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Count | Should -Be $table2count.Count
    }

    It "copies the table data to another instance" {
        $null = Copy-DbaDbTableData -SqlInstance $script:instance1 -Destination $script:instance2 -Database tempdb -Table tempdb.dbo.dbatoolsci_example -DestinationTable dbatoolsci_example3
        $table1count = $db.Query("select id from dbo.dbatoolsci_example")
        $table2count = $db2.Query("select id from dbo.dbatoolsci_example3")
        $table1count.Count | Should -Be $table2count.Count
    }

    It "supports piping" {
        $null = Get-DbaDbTable -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example2 -Truncate
        $table1count = $db.Query("select id from dbo.dbatoolsci_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Count | Should -Be $table2count.Count
    }

    It "supports piping more than one table" {
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example2, dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example3
        $results.Count | Should -Be 2
        $results.RowsCopied | Measure-Object -Sum | Select-Object -Expand Sum | Should -Be 20
    }

    It "opens and closes connections properly" {
        #regression test, see #3468
        $results = Get-DbaDbTable -SqlInstance $script:instance1 -Database tempdb -Table 'dbo.dbatoolsci_example', 'dbo.dbatoolsci_example4' | Copy-DbaDbTableData -Destination $script:instance2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
        $results.Count | Should -Be 2
        $table1dbcount = $db.Query("select id from dbo.dbatoolsci_example")
        $table4dbcount = $db2.Query("select id from dbo.dbatoolsci_example4")
        $table1db2count = $db.Query("select id from dbo.dbatoolsci_example")
        $table4db2count = $db2.Query("select id from dbo.dbatoolsci_example4")
        $table1dbcount.Count | Should -Be $table1db2count.Count
        $table4dbcount.Count | Should -Be $table4db2count.Count
        $results[0].RowsCopied | Should -Be 10
        $results[1].RowsCopied | Should -Be 13
        $table4db2check = $db2.Query("select id from dbo.dbatoolsci_example4 where id = 1")
        $table4db2check.Count | Should -Be 13
    }

    It "Should return nothing if Source and Destination are same" {
        $result = Copy-DbaDbTableData -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example -Truncate
        $result | Should -Be $null
    }

    It "Should warn if the destinaton table doesn't exist" {
        $result = Copy-DbaDbTableData -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning
        $result | Should -Be $null
        $tablewarning | Should -match Auto
    }

    It "automatically creates the table" {
        $result = Copy-DbaDbTableData -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_willexist -AutoCreateTable
        $result.DestinationTable | Should -Be 'dbatoolsci_willexist'
    }

    It "Should warn if the source database doesn't exist" {
        $result = Copy-DbaDbTableData -SqlInstance $script:instance2 -Database tempdb_invalid -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning
        $result | Should -Be $null
        $tablewarning | Should -match "cannot open database"
    }

    It "Copy data using a query that relies on the default source database" {
        $result = Copy-DbaDbTableData -SqlInstance $script:instance2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) Id FROM dbo.dbatoolsci_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
        $result.RowsCopied | Should -Be 1
    }

    It "Copy data using a query that uses a 3 part query" {
        $result = Copy-DbaDbTableData -SqlInstance $script:instance2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) Id FROM tempdb.dbo.dbatoolsci_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
        $result.RowsCopied | Should -Be 1
    }
}