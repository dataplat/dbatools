param($ModuleName = 'dbatools')

Describe "Find-DbaSimilarTable" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaSimilarTable
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have SchemaName as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter SchemaName -Type String -Not -Mandatory
        }
        It "Should have TableName as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter TableName -Type String -Not -Mandatory
        }
        It "Should have ExcludeViews as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeViews -Type Switch -Not -Mandatory
        }
        It "Should have IncludeSystemDatabases as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDatabases -Type Switch -Not -Mandatory
        }
        It "Should have MatchPercentThreshold as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter MatchPercentThreshold -Type Int32 -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Testing if similar tables are discovered" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb
            $db.Query("CREATE TABLE dbatoolsci_table1 (id int identity, fname varchar(20), lname char(5), lol bigint, whatever datetime)")
            $db.Query("CREATE TABLE dbatoolsci_table2 (id int identity, fname varchar(20), lname char(5), lol bigint, whatever datetime)")
        }
        AfterAll {
            $db.Query("DROP TABLE dbatoolsci_table1")
            $db.Query("DROP TABLE dbatoolsci_table2")
        }

        It "returns at least two rows with correct database IDs and 100% match" {
            $results = Find-DbaSimilarTable -SqlInstance $global:instance1 -Database tempdb | Where-Object Table -Match dbatoolsci
            $results.Count | Should -BeGreaterOrEqual 2
            $results.OriginalDatabaseId | Should -Be $db.ID, $db.ID
            $results.MatchingDatabaseId | Should -Be $db.ID, $db.ID
            $results | ForEach-Object { $_.MatchPercent | Should -Be 100 }
        }
    }
}
