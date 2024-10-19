param($ModuleName = 'dbatools')

Describe "Test-DbaDbCollation" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDbCollation
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "testing collation of a single database" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $db1 = "dbatoolsci_collation"
            Get-DbaDatabase -SqlInstance $server -Database $db1 | Remove-DbaDatabase
            $server.Query("CREATE DATABASE $db1")
        }
        AfterAll {
            Get-DbaDatabase -SqlInstance $server -Database $db1 | Remove-DbaDatabase
        }

        It "confirms the db is the same collation as the server" {
            $result = Test-DbaDbCollation -SqlInstance $global:instance1 -Database $db1
            $result.IsEqual | Should -BeTrue
        }
    }
}
