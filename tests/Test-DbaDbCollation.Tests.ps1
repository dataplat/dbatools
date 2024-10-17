param($ModuleName = 'dbatools')

Describe "Test-DbaDbCollation" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDbCollation
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "testing collation of a single database" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $env:instance1
            $db1 = "dbatoolsci_collation"
            Get-DbaDatabase -SqlInstance $server -Database $db1 | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $db1")
        }
        AfterAll {
            Get-DbaDatabase -SqlInstance $server -Database $db1 | Remove-DbaDatabase -Confirm:$false
        }

        It "confirms the db is the same collation as the server" {
            $result = Test-DbaDbCollation -SqlInstance $env:instance1 -Database $db1
            $result.IsEqual | Should -BeTrue
        }
    }
}
