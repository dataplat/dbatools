#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbDbccCheckConstraint",
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
                "Object",
                "AllConstraints",
                "AllErrorMessages",
                "NoInformationalMessages",
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

        $splatConnection = @{
            SqlInstance = $TestConfig.InstanceSingle
        }
        $server = Connect-DbaInstance @splatConnection
        $random = Get-Random
        $tableName = "dbatools_CheckConstraintTbl1"
        $check1 = "chkTab1"
        $dbname = "dbatoolsci_dbccCheckConstraint$random"

        $null = $server.Query("CREATE DATABASE $dbname")
        $null = $server.Query("CREATE TABLE $tableName (Col1 int, Col2 char (30))", $dbname)
        $null = $server.Query("INSERT $tableName(Col1, Col2) VALUES (100, 'Hello')", $dbname)
        $null = $server.Query("ALTER TABLE $tableName WITH NOCHECK ADD CONSTRAINT $check1 CHECK (Col1 > 100); ", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output" {
        BeforeDiscovery {
            # -ForEach is read while Pester discovers the tests, so the list has to be built here.
            # Built in BeforeAll and consumed by a foreach around the It block, as it was before,
            # the list is still empty at discovery and not a single one of these tests existed.
            $expectedProperty = @(
                @{ PropertyName = "ComputerName" }
                @{ PropertyName = "InstanceName" }
                @{ PropertyName = "SqlInstance" }
                @{ PropertyName = "Database" }
                @{ PropertyName = "Cmd" }
                @{ PropertyName = "Output" }
                @{ PropertyName = "Table" }
                @{ PropertyName = "Constraint" }
                @{ PropertyName = "Where" }
            )
        }

        BeforeAll {
            $splatCheckConstraint = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbname
                Object      = $tableName
            }
            $result = Invoke-DbaDbDbccCheckConstraint @splatCheckConstraint
        }

        It "Should return property: <PropertyName>" -ForEach $expectedProperty {
            $p = $result[0].PSObject.Properties[$PropertyName]
            $p.Name | Should -Be $PropertyName
        }

        It "Returns correct results" {
            $result.Database -match $dbname | Should -Be $true
            $result.Table -match $tableName | Should -Be $true
            $result.Constraint -match $check1 | Should -Be $true
            $result.Output.Substring(0, 25) -eq "DBCC execution completed." | Should -Be $true
        }
    }
}