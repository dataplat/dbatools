#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbIdentity",
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
                "Table",
                "ReSeedValue",
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
        $tableName1 = "dbatools_getdbtbl1"
        $tableName2 = "dbatools_getdbtbl2"

        $dbname = "dbatoolsci_getdbUsage$random"
        $null = $server.Query("CREATE DATABASE $dbname")
        $null = $server.Query("CREATE TABLE $tableName1 (Id int NOT NULL IDENTITY (125, 1), Value varchar(5))", $dbname)
        $null = $server.Query("CREATE TABLE $tableName2 (Id int NOT NULL IDENTITY (  5, 1), Value varchar(5))", $dbname)

        $null = $server.Query("INSERT $tableName1(Value) SELECT 1", $dbname)
        $null = $server.Query("INSERT $tableName2(Value) SELECT 2", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Validate standard output" {
        BeforeAll {
            $props = "ComputerName", "InstanceName", "SqlInstance", "Database", "Table", "Cmd", "IdentityValue", "ColumnValue", "Output"
            $result = Set-DbaDbIdentity -SqlInstance $TestConfig.instance2 -Database $dbname -Table $tableName1, $tableName2 -Confirm:$false
        }

        It "Should return property: <_>" -ForEach $props {
            $p = $result[0].PSObject.Properties[$PSItem]
            $p.Name | Should -Be $PSItem
        }

        It "Returns results for each table" {
            $result.Count -eq 2 | Should -Be $true
        }

        It "Returns correct results" {
            $result[1].IdentityValue -eq 5 | Should -Be $true
        }
    }

    Context "Reseed option returns correct results" {
        It "Returns correct results" {
            $result = Set-DbaDbIdentity -SqlInstance $TestConfig.instance2 -Database $dbname -Table $tableName2 -ReSeedValue 400 -Confirm:$false
            $result.cmd -eq "DBCC CHECKIDENT('$tableName2', RESEED, 400)" | Should -Be $true
            $result.IdentityValue -eq "5." | Should -Be $true
        }
    }
}