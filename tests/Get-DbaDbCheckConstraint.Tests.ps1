#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbCheckConstraint",
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
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Set up test database and tables for check constraint testing
        $testServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $random = Get-Random
        $testTableName1 = "dbatools_getdbtbl1"
        $testTableName2 = "dbatools_getdbtbl2"
        $testCkName = "dbatools_getdbck"
        $testDbName = "dbatoolsci_getdbfk$random"

        $testServer.Query("CREATE DATABASE $testDbName")
        $testServer.Query("CREATE TABLE $testTableName1 (idTbl1 INT PRIMARY KEY)", $testDbName)
        $testServer.Query("CREATE TABLE $testTableName2 (idTbl2 INT, idTbl1 INT, id3 INT)", $testDbName)
        $testServer.Query("ALTER TABLE $testTableName2 ADD CONSTRAINT $testCkName CHECK (id3 > 10)", $testDbName)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup test database
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDbName | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Command actually works" {
        It "returns no check constraints from excluded DB with -ExcludeDatabase" {
            $results = Get-DbaDbCheckConstraint -SqlInstance $TestConfig.instance2 -ExcludeDatabase master
            $results | Where-Object { $PSItem.Database -eq "master" } | Should -BeNullOrEmpty
        }

        It "returns only check constraints from selected DB with -Database" {
            $results = Get-DbaDbCheckConstraint -SqlInstance $TestConfig.instance2 -Database $testDbName
            $results | Where-Object { $PSItem.Database -ne "master" } | Should -HaveCount 1
            $results.DatabaseId | Get-Unique | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDbName).Id
        }

        It "Should include test check constraint: $testCkName" {
            $results = Get-DbaDbCheckConstraint -SqlInstance $TestConfig.instance2 -Database $testDbName -ExcludeSystemTable
            $results | Where-Object Name -eq $testCkName | Select-Object -ExpandProperty Name | Should -Be $testCkName
        }

        It "Should exclude system tables" {
            $results = Get-DbaDbCheckConstraint -SqlInstance $TestConfig.instance2 -Database master -ExcludeSystemTable
            $results | Where-Object Name -eq "spt_fallback_db" | Should -BeNullOrEmpty
        }
    }
}