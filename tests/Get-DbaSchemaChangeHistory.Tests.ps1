#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSchemaChangeHistory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Since",
                "Object",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing if schema changes are discovered" {
        BeforeAll {
            $schemaChangeDb = Get-DbaDatabase -SqlInstance $testConfig.InstanceSingle -Database tempdb
            $schemaChangeDb.Query("CREATE TABLE dbatoolsci_schemachange (id int identity)")
            $schemaChangeDb.Query("EXEC sp_rename 'dbatoolsci_schemachange', 'dbatoolsci_schemachange1'")

            $schemaResults = Get-DbaSchemaChangeHistory -SqlInstance $testConfig.InstanceSingle -Database tempdb
        }

        AfterAll {
            $cleanupDb = Get-DbaDatabase -SqlInstance $testConfig.InstanceSingle -Database tempdb
            $cleanupDb.Query("DROP TABLE dbo.dbatoolsci_schemachange1")
        }

        It "notices dbatoolsci_schemachange changed" {
            $schemaResults.Object -match "dbatoolsci_schemachange" | Should -Be $true
        }
    }
}
