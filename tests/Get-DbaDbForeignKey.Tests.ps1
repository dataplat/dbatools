#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbForeignKey",
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
                "ExcludeSystemTable",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $random = Get-Random
        $tableName = "dbatools_getdbtbl1"
        $tableName2 = "dbatools_getdbtbl2"
        $fkName = "dbatools_getdbfk"
        $dbname = "dbatoolsci_getdbfk$random"
        $server.Query("CREATE DATABASE $dbname")
        $server.Query("CREATE TABLE $tableName (idTbl1 INT PRIMARY KEY)", $dbname)
        $server.Query("CREATE TABLE $tableName2 (idTbl2 INT, idTbl1 INT)", $dbname)
        $server.Query("ALTER TABLE $tableName2 ADD CONSTRAINT $fkName FOREIGN KEY (idTbl1) REFERENCES $tableName (idTbl1) ON UPDATE NO ACTION ON DELETE NO ACTION ", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command actually works" {
        It "returns no foreign keys from excluded DB with -ExcludeDatabase" {
            $results = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -ExcludeDatabase master
            ($results | Where-Object Database -eq "master").Count | Should -BeExactly 0
        }

        It "returns only foreign keys from selected DB with -Database" {
            $results = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -Database $dbname
            ($results | Where-Object Database -ne "master").Count | Should -BeExactly 1
        }

        It "Should include test foreign keys: $fkName" {
            $results = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -Database $dbname -ExcludeSystemTable
            ($results | Where-Object Name -eq $fkName).Name | Should -Be $fkName
        }

        It "Should exclude system tables" {
            $results = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -Database master -ExcludeSystemTable
            ($results | Where-Object Name -eq "spt_fallback_db") | Should -BeNullOrEmpty
        }
    }

    Context "Parameters are returned correctly" {
        BeforeAll {
            $results = Get-DbaDbForeignKey -SqlInstance $TestConfig.instance2 -ExcludeDatabase master
        }

        It "Has the correct default properties" {
            $expectedStdProps = @(
                "ComputerName",
                "CreateDate",
                "Database",
                "DateLastModified",
                "ID",
                "InstanceName",
                "IsChecked",
                "IsEnabled",
                "Name",
                "NotForReplication",
                "ReferencedKey",
                "ReferencedTable",
                "ReferencedTableSchema",
                "SqlInstance",
                "Schema",
                "Table"
            )
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedStdProps | Sort-Object)
        }

        It "Has the correct properties" {
            $expectedProps = @(
                "Columns",
                "ComputerName",
                "CreateDate",
                "Database",
                "DatabaseEngineEdition",
                "DatabaseEngineType",
                "DateLastModified",
                "DeleteAction",
                "ExecutionManager",
                "ExtendedProperties",
                "ID",
                "InstanceName",
                "IsChecked",
                "IsDesignMode",
                "IsEnabled",
                "IsFileTableDefined",
                "IsMemoryOptimized",
                "IsSystemNamed",
                "Name",
                "NotForReplication",
                "Parent",
                "ParentCollection",
                "Properties",
                "ReferencedKey",
                "ReferencedTable",
                "ReferencedTableSchema",
                "ScriptReferencedTable",
                "ScriptReferencedTableSchema",
                "ServerVersion",
                "SqlInstance",
                "State",
                "Schema",
                "Table",
                "UpdateAction",
                "Urn",
                "UserData"
            )
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }
    }
}