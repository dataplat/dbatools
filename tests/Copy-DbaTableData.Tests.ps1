$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        $db2 = Get-DbaDatabase -SqlInstance $script:instance2 -Database tempdb
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example (id int);
            INSERT dbo.dbatoolsci_example
            SELECT top 100 1
            FROM sys.objects")
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example2 (id int)")
        $null = $db2.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
    }
    AfterAll {
        $null = $db.Query("DROP TABLE dbo.dbatoolsci_example")
        $null = $db.Query("DROP TABLE dbo.dbatoolsci_example2")
        $null = $db2.Query("DROP TABLE dbo.dbatoolsci_example3")
    }

    It "copies the table data" {
        $null = Copy-DbaTableData -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example2
        $table1count = $db.Query("select id from dbo.dbatoolsci_example")
        $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table1count.Count -eq $table2count.Count
    }

    It "copies the table data to another instance" {
        $null = Copy-DbaTableData -SqlInstance $script:instance1 -Destination $script:instance2 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example3
        $table1count = $db.Query("select id from dbo.dbatoolsci_example")
        $table2count = $db2.Query("select id from dbo.dbatoolsci_example3")
        $table1count.Count -eq $table2count.Count
    }

    It "supports piping" {
        $results = Get-DbaTable -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example | Copy-DbaTableData -DestinationTable dbatoolsci_example2
        $table3count = $db.Query("select id from dbo.dbatoolsci_example2")
        $table3count.Count -gt $table2count.Count
    }

    It "supports piping more than one table" {
        $results = Get-DbaTable -SqlInstance $script:instance1 -Database tempdb -Table dbatoolsci_example2, dbatoolsci_example | Copy-DbaTableData -DestinationTable dbatoolsci_example2
        $results.Count -eq 2
    }
}