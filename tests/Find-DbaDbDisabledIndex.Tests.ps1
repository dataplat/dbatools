#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaDbDisabledIndex",
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
                "NoClobber",
                "Append",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $random = Get-Random
            $databaseName1 = "dbatoolsci1_$random"
            $databaseName2 = "dbatoolsci2_$random"
            $db1 = New-DbaDatabase -SqlInstance $server -Name $databaseName1
            $db2 = New-DbaDatabase -SqlInstance $server -Name $databaseName2
            $indexName = "dbatoolsci_index_$random"
            $tableName = "dbatoolsci_table_$random"
            $sql = "create table $tableName (col1 int)
                    create index $indexName on $tableName (col1)
                    ALTER INDEX $indexName ON $tableName DISABLE;"
            $null = $db1.Query($sql)
            $null = $db2.Query($sql)

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $db1, $db2 | Remove-DbaDatabase

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should find disabled index: $indexName" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle
            ($results | Where-Object IndexName -eq $indexName).Count | Should -BeExactly 2
            ($results | Where-Object DatabaseName -in $databaseName1, $databaseName2).Count | Should -BeExactly 2
            ($results | Where-Object DatabaseId -in $db1.Id, $db2.Id).Count | Should -BeExactly 2
        }

        It "Should find disabled index: $indexName for specific database" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database $databaseName1
            $results.IndexName | Should -Be $indexName
            $results.DatabaseName | Should -Be $databaseName1
            $results.DatabaseId | Should -Be $db1.Id
        }

        It "Should exclude specific database" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $databaseName1
            $results.IndexName | Should -Be $indexName
            $results.DatabaseName | Should -Be $databaseName2
            $results.DatabaseId | Should -Be $db2.Id
        }

        It "Returns output of the documented type" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database $databaseName1
            $results | Should -Not -BeNullOrEmpty
            $results[0] | Should -BeOfType System.Data.DataRow
        }

        It "Has the expected properties" {
            $results = Find-DbaDbDisabledIndex -SqlInstance $TestConfig.InstanceSingle -Database $databaseName1
            $results | Should -Not -BeNullOrEmpty
            $expectedProps = @(
                "DatabaseName",
                "DatabaseId",
                "SchemaName",
                "TableName",
                "ObjectId",
                "IndexName",
                "IndexId",
                "TypeDesc"
            )
            foreach ($prop in $expectedProps) {
                $results[0].Table.Columns.ColumnName | Should -Contain $prop -Because "property '$prop' should be present on the output object"
            }
        }
    }
}