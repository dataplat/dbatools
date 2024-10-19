param($ModuleName = 'dbatools')

Describe "Get-DbaSchemaChangeHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSchemaChangeHistory
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Since",
                "Object"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
            $CommandUnderTest | Should -HaveParameter EnableException -Switch
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
