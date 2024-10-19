param($ModuleName = 'dbatools')

Describe "Get-DbaSchemaChangeHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSchemaChangeHistory
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
        It "Should have Since as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Since
        }
        It "Should have Object as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Object
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Get-DbaSchemaChangeHistory Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    Context "Testing if schema changes are discovered" {
        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb
            $db.Query("CREATE TABLE dbatoolsci_schemachange (id int identity)")
            $db.Query("EXEC sp_rename 'dbatoolsci_schemachange', 'dbatoolsci_schemachange1'")
        }
        AfterAll {
            $db.Query("DROP TABLE dbo.dbatoolsci_schemachange1")
        }

        It "notices dbatoolsci_schemachange changed" {
            $results = Get-DbaSchemaChangeHistory -SqlInstance $global:instance1 -Database tempdb
            $results.Object -match 'dbatoolsci_schemachange' | Should -Be $true
        }
    }
}
