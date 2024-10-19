param($ModuleName = 'dbatools')

Describe "Get-DbaCustomError" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaCustomError
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $sql = "EXEC msdb.dbo.sp_addmessage 54321, 9, N'Dbatools is Awesome!';"
            $server.Query($sql)
        }
        AfterAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $sql = "EXEC msdb.dbo.sp_dropmessage 54321;"
            $server.Query($sql)
        }

        It "Gets the custom errors" {
            $results = Get-DbaCustomError -SqlInstance $global:instance1
            $results | Should -Not -BeNullOrEmpty
            $results.Text | Should -Be "Dbatools is Awesome!"
            $results.LanguageID | Should -Be 1033
            $results.ID | Should -Be 54321
        }
    }
}
