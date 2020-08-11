$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Destination', 'DestinationSqlCredential', 'Database', 'DestinationDatabase', 'View', 'Query', 'AutoCreateTable', 'BatchSize', 'NotifyAfter', 'DestinationTable', 'NoTableLock', 'CheckConstraints', 'FireTriggers', 'KeepIdentity', 'KeepNulls', 'Truncate', 'bulkCopyTimeOut', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
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

    It "copies the table data" {
        $null = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example -DestinationTable dbatoolsci_example2
        $table1count = $db.Query("select id from dbo.dbatoolsci_view_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Count | Should -Be $table2count.Count
    }

    It "copies the table data to another instance" {
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

    It "supports piping more than one table" {
        $results = Get-DbaDbView -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example2, dbatoolsci_view_example | Copy-DbaDbViewData -DestinationTable dbatoolsci_example3
        $results.Count | Should -Be 2
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
        $result | Should Be $null
        $tablewarning | Should -match "Cannot copy dbatoolsci_view_example into itself"
    }

    It "Should warn if the destination table doesn't exist" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example -DestinationTable dbatoolsci_view_does_not_exist -WarningVariable tablewarning
        $tablewarning | Should -match Auto
    }

    It "automatically creates the table" {
        $result = Copy-DbaDbViewData -SqlInstance $script:instance1 -Database tempdb -View dbatoolsci_view_example -DestinationTable dbatoolsci_view_will_exist -AutoCreateTable
        $result.DestinationTable | Should -Be 'dbatoolsci_view_will_exist'
    }
}