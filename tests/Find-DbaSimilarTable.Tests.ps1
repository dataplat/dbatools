param($ModuleName = 'dbatools')

Describe "Find-DbaSimilarTable" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaSimilarTable
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[] -Mandatory:$false
        }
        It "Should have SchemaName as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter SchemaName -Type System.String -Mandatory:$false
        }
        It "Should have TableName as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter TableName -Type System.String -Mandatory:$false
        }
        It "Should have ExcludeViews as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeViews -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have IncludeSystemDatabases as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDatabases -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have MatchPercentThreshold as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter MatchPercentThreshold -Type System.Int32 -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
