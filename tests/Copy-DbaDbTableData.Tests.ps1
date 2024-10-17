param($ModuleName = 'dbatools')

Describe "Copy-DbaDbTableData" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb
        $db2 = Get-DbaDatabase -SqlInstance $global:instance2 -Database tempdb
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

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaDbTableData
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Destination as a parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have DestinationDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationDatabase -Type String
        }
        It "Should have Table as a parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type String[]
        }
        It "Should have View as a parameter" {
            $CommandUnderTest | Should -HaveParameter View -Type String[]
        }
        It "Should have Query as a parameter" {
            $CommandUnderTest | Should -HaveParameter Query -Type String
        }
        It "Should have AutoCreateTable as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AutoCreateTable -Type Switch
        }
        It "Should have BatchSize as a parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSize -Type Int32
        }
        It "Should have NotifyAfter as a parameter" {
            $CommandUnderTest | Should -HaveParameter NotifyAfter -Type Int32
        }
        It "Should have DestinationTable as a parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationTable -Type String
        }
        It "Should have NoTableLock as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoTableLock -Type Switch
        }
        It "Should have CheckConstraints as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter CheckConstraints -Type Switch
        }
        It "Should have FireTriggers as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter FireTriggers -Type Switch
        }
        It "Should have KeepIdentity as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter KeepIdentity -Type Switch
        }
        It "Should have KeepNulls as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter KeepNulls -Type Switch
        }
        It "Should have Truncate as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Truncate -Type Switch
        }
        It "Should have BulkCopyTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter BulkCopyTimeout -Type Int32
        }
        It "Should have CommandTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter CommandTimeout -Type Int32
        }
        It "Should have UseDefaultFileGroup as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter UseDefaultFileGroup -Type Switch
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type TableViewBase[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Data movement" {
        It "copies the table data" {
            $results = Copy-DbaDbTableData -SqlInstance $global:instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example2
            $table1count = $db.Query("select id from dbo.dbatoolsci_example")
            $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
            $results.SourceDatabaseID | Should -Be $db.ID
            $results.DestinationDatabaseID | Should -Be $db.ID
        }

        It "copies the table data to another instance" {
            $null = Copy-DbaDbTableData -SqlInstance $global:instance1 -Destination $global:instance2 -Database tempdb -Table tempdb.dbo.dbatoolsci_example -DestinationTable dbatoolsci_example3
            $table1count = $db.Query("select id from dbo.dbatoolsci_example")
            $table2count = $db2.Query("select id from dbo.dbatoolsci_example3")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "Copy data using a query that relies on the default source database" {
            $result = Copy-DbaDbTableData -SqlInstance $global:instance2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) Id FROM dbo.dbatoolsci_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
            $result.RowsCopied | Should -Be 1
        }

        It "Copy data using a query that uses a 3 part query" {
            $result = Copy-DbaDbTableData -SqlInstance $global:instance2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) Id FROM tempdb.dbo.dbatoolsci_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
            $result.RowsCopied | Should -Be 1
        }
    }

    Context "Functionality checks" {
        It "supports piping" {
            $null = Get-DbaDbTable -SqlInstance $global:instance1 -Database tempdb -Table dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example2 -Truncate
            $table1count = $db.Query("select id from dbo.dbatoolsci_example")
            $table2count = $db.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "supports piping more than one table" {
            $results = Get-DbaDbTable -SqlInstance $global:instance1 -Database tempdb -Table dbatoolsci_example2, dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example3
            $results.Count | Should -Be 2
            $results.RowsCopied | Measure-Object -Sum | Select-Object -Expand Sum | Should -Be 20
        }

        It "opens and closes connections properly" {
            $results = Get-DbaDbTable -SqlInstance $global:instance1 -Database tempdb -Table 'dbo.dbatoolsci_example', 'dbo.dbatoolsci_example4' | Copy-DbaDbTableData -Destination $global:instance2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
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

        It "Should return nothing if Source and Destination are same" {
            $result = Copy-DbaDbTableData -SqlInstance $global:instance1 -Database tempdb -Table dbatoolsci_example -Truncate
            $result | Should -BeNullOrEmpty
        }

        It "Should warn if the destinaton table doesn't exist" {
            $result = Copy-DbaDbTableData -SqlInstance $global:instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning 3> $null
            $result | Should -BeNullOrEmpty
            $tablewarning | Should -Match Auto
        }

        It "automatically creates the table" {
            $result = Copy-DbaDbTableData -SqlInstance $global:instance1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_willexist -AutoCreateTable
            $result.DestinationTable | Should -Be 'dbatoolsci_willexist'
        }

        It "Should warn if the source database doesn't exist" {
            $result = Copy-DbaDbTableData -SqlInstance $global:instance2 -Database tempdb_invalid -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning 3> $null
            $result | Should -BeNullOrEmpty
            $tablewarning | Should -Match "cannot open database"
        }
    }
}
