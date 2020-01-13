$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Destination', 'DestinationSqlCredential', 'Database', 'DestinationDatabase', 'Table', 'Query', 'AutoCreateTable', 'BatchSize', 'NotifyAfter', 'DestinationTable', 'NoTableLock', 'CheckConstraints', 'FireTriggers', 'KeepIdentity', 'KeepNulls', 'Truncate', 'bulkCopyTimeOut', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_exview AS SELECT * FROM dbo.dbatoolsci_example")
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_exview2 AS SELECT * FROM dbo.dbatoolsci_example2")
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_exview3 AS SELECT * FROM dbo.dbatoolsci_example3")
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_exview4 AS SELECT * FROM dbo.dbatoolsci_example4")
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
            $null = $db.Query("DROP VIEW dbo.dbatoolsci_exview")
            $null = $db.Query("DROP VIEW dbo.dbatoolsci_exview2")
            $null = $db.Query("DROP VIEW dbo.dbatoolsci_exview3")
            $null = $db.Query("DROP VIEW dbo.dbatoolsci_exview4")
            $null = $db2.Query("DROP TABLE dbo.dbatoolsci_example3")
            $null = $db2.Query("DROP TABLE dbo.dbatoolsci_example4")
            $null = $db2.Query("DROP TABLE dbo.dbatoolsci_example")
            $null = $db.Query("DROP TABLE tempdb.dbo.dbatoolsci_willexist")
        } catch {
            $null = 1
        }
    }

    It "copies the table data" {
        $null = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_exview -DestinationTable dbatoolsci_example2
        $table1count = $db.Query("select id from dbo.dbatoolsci_exview")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Count | Should -Be $table2count.Count
    }

    It "copies the table data to another instance" {
        $null = Copy-DbaDbViewData -SqlInstance $script:instance1 -Destination $script:instance2 -Database tempdb -View dbatoolsci_exview -DestinationTable dbatoolsci_example3
        $table1count = $db.Query("select id from dbo.dbatoolsci_exview")
        $table2count = $db2.Query("select id from dbo.dbatoolsci_example3")
        $table1count.Count | Should -Be $table2count.Count
    }

    It "supports piping" {
        $null = Get-DbaDbView -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_exview | Copy-DbaDbViewData -DestinationTable dbatoolsci_example2 -Truncate
        $table1count = $db.Query("select id from dbo.dbatoolsci_view")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Count | Should -Be $table2count.Count
    }

    It "supports piping more than one table" {
        $results = Get-DbaDbView -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_exview2, dbatoolsci_exview | Copy-DbaDbViewData -DestinationTable dbatoolsci_example3
        $results.Count | Should -Be 2
    }

    It "opens and closes connections properly" {
        #regression test, see #3468
        $results = Get-DbaDbView -SqlInstance $script:instance1 -Database tempdb -View 'dbo.dbatoolsci_exview', 'dbo.dbatoolsci_exview4' | Copy-DbaDbViewData -Destination $script:instance2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
        $results.Count | Should -Be 2
        $table1dbcount = $db.Query("select id from dbo.dbatoolsci_exview")
        $table4dbcount = $db2.Query("select id from dbo.dbatoolsci_example4")
        $table1db2count = $db.Query("select id from dbo.dbatoolsci_exview")
        $table4db2count = $db2.Query("select id from dbo.dbatoolsci_example4")
        $table1dbcount.Count | Should -Be $table1db2count.Count
        $table4dbcount.Count | Should -Be $table4db2count.Count
        $results[0].RowsCopied | Should -Be 10
        $results[1].RowsCopied | Should -Be 13
        $table4db2check = $db2.Query("select id from dbo.dbatoolsci_example4 where id = 1")
        $table4db2check.Count | Should -Be 13
    }

    It "Should return nothing if Source and Destination are same" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_exview -Truncate
        $result | Should Be $null
    }

    It "Should warn if the destinaton table doesn't exist" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_exview -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning
        $tablewarning | Should -match Auto
    }

    It "automatically creates the table" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_exview -DestinationTable dbatoolsci_willexist -AutoCreateTable
        $result.DestinationTable | Should -Be 'dbatoolsci_willexist'
    }
}