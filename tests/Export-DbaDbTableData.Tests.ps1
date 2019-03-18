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

    It "exports the table data" {
        $null = Copy-DbaDbTableData -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example2
        $table1count = $db.Query("select id from dbo.dbatoolsci_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
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
    }
}