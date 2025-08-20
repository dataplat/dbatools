#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaSimilarTable",
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
                "SchemaName",
                "TableName",
                "ExcludeViews",
                "IncludeSystemDatabases",
                "MatchPercentThreshold",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing if similar tables are discovered" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempdb
            $db.Query("CREATE TABLE dbatoolsci_table1 (id int identity, fname varchar(20), lname char(5), lol bigint, whatever datetime)")
            $db.Query("CREATE TABLE dbatoolsci_table2 (id int identity, fname varchar(20), lname char(5), lol bigint, whatever datetime)")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempdb
            $db.Query("DROP TABLE dbatoolsci_table1")
            $db.Query("DROP TABLE dbatoolsci_table2")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns at least two rows" {
            # not an exact count because who knows
            $results = Find-DbaSimilarTable -SqlInstance $TestConfig.instance1 -Database tempdb | Where-Object Table -Match dbatoolsci

            $results.Status.Count -ge 2 | Should -Be $true
            $results.OriginalDatabaseId | Should -Be $db.ID, $db.ID
            $results.MatchingDatabaseId | Should -Be $db.ID, $db.ID
        }

        It "matches 100% for the test tables" {
            $results = Find-DbaSimilarTable -SqlInstance $TestConfig.instance1 -Database tempdb | Where-Object Table -Match dbatoolsci

            foreach ($result in $results) {
                $result.MatchPercent -eq 100 | Should -Be $true
            }
        }
    }
}