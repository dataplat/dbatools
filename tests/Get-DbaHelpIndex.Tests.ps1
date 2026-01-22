#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaHelpIndex",
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
                "InputObject",
                "ObjectName",
                "IncludeStats",
                "IncludeDataTypes",
                "Raw",
                "IncludeFragmentation",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $dbname = "dbatoolsci_$random"
        $server.Query("CREATE DATABASE $dbname")
        $server.Query("Create Table Test (col1 varchar(50) PRIMARY KEY, col2 int)", $dbname)
        $server.Query("Insert into test values ('value1',1),('value2',2)", $dbname)
        $server.Query("create statistics dbatools_stats on test (col2)", $dbname)
        $server.Query("select * from test", $dbname)
        $server.Query("create table t1(c1 int,c2 int,c3 int,c4 int)", $dbname)
        $server.Query("create nonclustered index idx_1 on t1(c1) include(c3)", $dbname)
        $server.Query("create table t2(c1 int,c2 int,c3 int,c4 int)", $dbname)
        $server.Query("create nonclustered index idx_1 on t2(c1,c2) include(c3,c4)", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command works for indexes" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ObjectName Test
        }

        It "Results should be returned" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Gets results for the test table" {
            $results.object | Should -Be "[dbo].[test]"
        }

        It "Correctly returns IndexRows of 2" {
            $results.IndexRows | Should -Be 2
        }

        It "Should not return datatype for col1" {
            $results.KeyColumns | Should -Not -Match "varchar"
        }
    }
    Context "Command works when including statistics" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ObjectName Test -IncludeStats | Where-Object { $PSItem.Statistics }
        }

        It "Results should be returned" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Returns dbatools_stats from test object" {
            $results.Statistics | Should -Contain "dbatools_stats"
        }
    }
    Context "Command output includes data types" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ObjectName Test -IncludeDataTypes
        }

        It "Results should be returned" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Returns varchar for col1" {
            $results.KeyColumns | Should -Match "varchar"
        }
    }
    Context "Formatting is correct" {
        It "Formatted as strings" {
            $results = Get-DbaHelpIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ObjectName Test -IncludeFragmentation
            $results.IndexReads | Should -BeOfType "String"
            $results.IndexUpdates | Should -BeOfType "String"
            $results.Size | Should -BeOfType "String"
            $results.IndexRows | Should -BeOfType "String"
            $results.IndexLookups | Should -BeOfType "String"
            $results.StatsSampleRows | Should -BeOfType "String"
            $results.IndexFragInPercent | Should -BeOfType "String"
        }
    }
    Context "Formatting is correct for raw" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ObjectName Test -raw -IncludeFragmentation
        }

        It "Formatted as Long" {
            $results.IndexReads | Should -BeOfType "Long"
            $results.IndexUpdates | Should -BeOfType "Long"
            $results.Size | Should -BeOfType "dbasize"
            $results.IndexRows | Should -BeOfType "Long"
            $results.IndexLookups | Should -BeOfType "Long"
        }

        It "Formatted as Double" {
            $results.IndexFragInPercent | Should -BeOfType "Double"
        }
    }
    Context "Result is correct for tables having the indexes with the same names" {
        BeforeAll {
            $results = Get-DbaHelpIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        }

        It "Table t1 has correct index key columns and included columns" {
            $results.where( { $PSItem.object -eq "[dbo].[t1]" }).KeyColumns | Should -Be "c1"
            $results.where( { $PSItem.object -eq "[dbo].[t1]" }).IncludeColumns | Should -Be "c3"
        }

        It "Table t2 has correct index key columns and included columns" {
            $results.where( { $PSItem.object -eq "[dbo].[t2]" }).KeyColumns | Should -Be "c1, c2"
            $results.where( { $PSItem.object -eq "[dbo].[t2]" }).IncludeColumns | Should -Be "c3, c4"
        }
    }
    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaHelpIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ObjectName Test -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Object",
                "Index",
                "Statistics",
                "IndexType",
                "KeyColumns",
                "IncludeColumns",
                "FilterDefinition",
                "FillFactor",
                "DataCompression",
                "IndexReads",
                "IndexUpdates",
                "Size",
                "IndexRows",
                "IndexLookups",
                "MostRecentlyUsed",
                "StatsSampleRows",
                "StatsRowMods",
                "HistogramSteps",
                "StatsLastUpdated"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
    Context "Output with -IncludeFragmentation" {
        BeforeAll {
            $result = Get-DbaHelpIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ObjectName Test -IncludeFragmentation -EnableException
        }

        It "Includes IndexFragInPercent property" {
            $result.PSObject.Properties.Name | Should -Contain "IndexFragInPercent"
        }
    }
    Context "Output with -IncludeStats" {
        BeforeAll {
            $result = Get-DbaHelpIndex -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ObjectName Test -IncludeStats -EnableException
        }

        It "Returns statistics objects with Statistics property populated" {
            $statsResults = $result | Where-Object { $null -ne $_.Statistics -and $_.Statistics -ne "" }
            $statsResults | Should -Not -BeNullOrEmpty
        }
    }
}