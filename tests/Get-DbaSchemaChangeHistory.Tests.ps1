#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSchemaChangeHistory",
    $PSDefaultParameterValues = (Get-TestConfig).Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = (Get-TestConfig).CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Since",
                "Object",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing if schema changes are discovered" {
        BeforeAll {
            $testConfig = Get-TestConfig
            $schemaChangeDb = Get-DbaDatabase -SqlInstance $testConfig.instance1 -Database tempdb
            $schemaChangeDb.Query("CREATE TABLE dbatoolsci_schemachange (id int identity)")
            $schemaChangeDb.Query("EXEC sp_rename 'dbatoolsci_schemachange', 'dbatoolsci_schemachange1'")
            
            $schemaResults = Get-DbaSchemaChangeHistory -SqlInstance $testConfig.instance1 -Database tempdb
        }
        
        AfterAll {
            $testConfig = Get-TestConfig
            $cleanupDb = Get-DbaDatabase -SqlInstance $testConfig.instance1 -Database tempdb
            $cleanupDb.Query("DROP TABLE dbo.dbatoolsci_schemachange1") -ErrorAction SilentlyContinue
        }

        It "notices dbatoolsci_schemachange changed" {
            $schemaResults.Object -match "dbatoolsci_schemachange" | Should -Be $true
        }
    }
}
