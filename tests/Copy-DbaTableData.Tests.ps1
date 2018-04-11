$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        $db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database tempdb
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example (id int);
            INSERT dbo.dbatoolsci_example
            SELECT top 10 1
            FROM sys.objects")
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example2 (id int)")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 1
            FROM sys.objects")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_example (id int)")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 2
            FROM sys.objects")
    }
    AfterAll {
        $null = $db.Query("DROP TABLE dbo.dbatoolsci_example")
        $null = $db.Query("DROP TABLE dbo.dbatoolsci_example2")
        $null = $db2.Query("DROP TABLE dbo.dbatoolsci_example3")
        $null = $db.Query("DROP TABLE dbo.dbatoolsci_example4")
        $null = $db2.Query("DROP TABLE dbo.dbatoolsci_example4")
        $null = $db2.Query("DROP TABLE dbo.dbatoolsci_example")
    }
    
    It "copies the table data" {
        $null = Copy-DbaTableData -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example2
        $table1count = $db.Query("select id from dbo.dbatoolsci_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Count | Should -Be $table2count.Count
    }
    
    It "copies the table data to another instance" {
        $null = Copy-DbaTableData -SqlInstance $script:instance1 -Destination $script:instance2 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example3
        $table1count = $db.Query("select id from dbo.dbatoolsci_example")
        $table2count = $db2.Query("select id from dbo.dbatoolsci_example3")
        $table1count.Count | Should -Be $table2count.Count
    }
    
    It "supports piping" {
        $null = Get-DbaTable -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example | Copy-DbaTableData -DestinationTable dbatoolsci_example2 -Truncate
        $table1count = $db.Query("select id from dbo.dbatoolsci_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Count | Should -Be $table2count.Count
    }
    
    It "supports piping more than one table" {
        $results = Get-DbaTable -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example2, dbatoolsci_example | Copy-DbaTableData -DestinationTable dbatoolsci_example2
        $results.Count | Should -Be 2
    }
    
    It "opens and closes connections properly" {
        #regression test, see #3468
        $results = Get-DbaTable -SqlInstance $script:instance1 -Database tempdb -Table 'dbo.dbatoolsci_example', 'dbo.dbatoolsci_example4' | Copy-DbaTableData -Destination $script:instance2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
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
}
