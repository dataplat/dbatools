$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'AutoCreateTable', 'BatchSize', 'bulkCopyTimeOut', 'CheckConstraints', 'Database', 'Destination', 'DestinationDatabase', 'DestinationSqlCredential', 'DestinationTable', 'EnableException', 'FireTriggers', 'InputObject', 'KeepIdentity', 'KeepNulls', 'NoTableLock', 'NotifyAfter', 'Query', 'SqlCredential', 'SqlInstance', 'Truncate', 'View'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        function Remove-TempObjects {
            param ($dbs)
            function Remove-TempObject {
                param ($db, $object)
                $db.Query("DECLARE @obj int = OBJECT_ID('$object'); IF @obj IS NOT NULL
                BEGIN
                    IF (SELECT type_desc FROM sys.objects WHERE object_id = @obj) = 'VIEW' DROP VIEW $object
                    ELSE DROP TABLE $object
                END")
            }
            foreach ($d in $dbs) {
                Remove-TempObject $d dbo.dbatoolsci_example
                Remove-TempObject $d dbo.dbatoolsci_example2
                Remove-TempObject $d dbo.dbatoolsci_example3
                Remove-TempObject $d dbo.dbatoolsci_example4
                Remove-TempObject $d dbo.dbatoolsci_view_example
                Remove-TempObject $d dbo.dbatoolsci_view_example2
                Remove-TempObject $d dbo.dbatoolsci_view_example3
                Remove-TempObject $d dbo.dbatoolsci_view_example4
                Remove-TempObject $d dbo.dbatoolsci_view_will_exist
                Remove-TempObject $d dbo.dbatoolsci_view_example_table
                Remove-TempObject $d dbo.dbatoolsci_view_example2_table
                Remove-TempObject $d dbo.dbatoolsci_view_example3_table
                Remove-TempObject $d dbo.dbatoolsci_view_example4_table
            }
        }
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        $db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database tempdb
        Remove-TempObjects $db, $db2
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
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_view_example AS SELECT * FROM dbo.dbatoolsci_example")
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_view_example2 AS SELECT * FROM dbo.dbatoolsci_example2")
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_view_example3 AS SELECT * FROM dbo.dbatoolsci_example3")
        $null = $db.Query("CREATE VIEW dbo.dbatoolsci_view_example4 AS SELECT * FROM dbo.dbatoolsci_example4")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_view_example (id int)")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_view_example3 (id int)")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_view_example4 (id int);
            INSERT dbo.dbatoolsci_view_example4
            SELECT top 13 2
            FROM sys.objects")
    }
    AfterAll {
        Remove-TempObjects $db, $db2
    }

    It "copies the view data" {
        $null = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example -DestinationTable dbatoolsci_example2
        $table1count = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Count | Should -Be $table2count.Count
    }

    It "copies the view data to another instance" {
        $null = Copy-DbaDbViewData -SqlInstance $script:instance1 -Destination $script:instance2 -Database tempdb -View dbatoolsci_view_example -DestinationTable dbatoolsci_view_example3
        $table1count = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table2count = $db2.Query("select id from dbo.dbatoolsci_view_example3")
        $table1count.Count | Should -Be $table2count.Count
    }

    It "supports piping" {
        $null = Get-DbaDbView -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example | Copy-DbaDbViewData -DestinationTable dbatoolsci_example2 -Truncate
        $table1count = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Count | Should -Be $table2count.Count
    }

    It "supports piping more than one view" {
        $results = Get-DbaDbView -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example2, dbatoolsci_view_example | Copy-DbaDbViewData -DestinationTable dbatoolsci_example3
        $results.Count | Should -Be 2
        $results.RowsCopied | Measure-Object -Sum | select -Expand Sum | Should -Be 20
    }

    It "opens and closes connections properly" {
        #regression test, see #3468
        $results = Get-DbaDbView -SqlInstance $script:instance1 -Database tempdb -View 'dbo.dbatoolsci_view_example', 'dbo.dbatoolsci_view_example4' | Copy-DbaDbViewData -Destination $script:instance2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
        $results.Count | Should -Be 2
        $table1dbcount = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table4dbcount = $db2.Query("select id from dbo.dbatoolsci_view_example4")
        $table1db2count = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table4db2count = $db2.Query("select id from dbo.dbatoolsci_view_example4")
        $table1dbcount.Count | Should -Be $table1db2count.Count
        $table4dbcount.Count | Should -Be $table4db2count.Count
        $results[0].RowsCopied | Should -Be 10
        $results[1].RowsCopied | Should -Be 13
        $table4db2check = $db2.Query("select id from dbo.dbatoolsci_view_example4 where id = 1")
        $table4db2check.Count | Should -Be 13
    }

    It "Should warn and return nothing if Source and Destination are same" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example -Truncate -WarningVariable tablewarning
        $result | Should -Be $null
        $tablewarning | Should -Match "Cannot copy dbatoolsci_view_example into itself"
    }

    It "Should warn if the destination table doesn't exist" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View tempdb.dbo.dbatoolsci_view_example -DestinationTable dbatoolsci_view_does_not_exist -WarningVariable tablewarning
        $result | Should -Be $null
        $tablewarning | Should -Match Auto
    }

    It "automatically creates the table" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example -DestinationTable dbatoolsci_view_will_exist -AutoCreateTable
        $result.DestinationTable | Should -Be 'dbatoolsci_view_will_exist'
    }

    It "Should warn if the source database doesn't exist" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance2 -Database tempdb_invalid -View dbatoolsci_view_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning
        $result | Should -Be $null
        $tablewarning | Should -Match "Failure"
    }

    It "Copy data using a query that relies on the default source database" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example -Query "SELECT TOP (1) Id FROM dbo.dbatoolsci_view_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
        $result.RowsCopied | Should -Be 1
    }

    It "Copy data using a query that uses a 3 part query" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example -Query "SELECT TOP (1) Id FROM tempdb.dbo.dbatoolsci_view_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
        $result.RowsCopied | Should -Be 1
    }
}