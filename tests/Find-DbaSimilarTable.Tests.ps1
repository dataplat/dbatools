param($ModuleName = 'dbatools')

Describe "Find-DbaSimilarTable" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaSimilarTable
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have SchemaName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SchemaName
        }
        It "Should have TableName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter TableName
        }
        It "Should have ExcludeViews as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeViews
        }
        It "Should have IncludeSystemDatabases as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDatabases
        }
        It "Should have MatchPercentThreshold as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter MatchPercentThreshold
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
