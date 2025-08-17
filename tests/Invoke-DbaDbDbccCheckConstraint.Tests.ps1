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
            SqlInstance = $TestConfig.instance2
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

        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Validate standard output" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Cmd",
                "Output",
                "Table",
                "Constraint",
                "Where"
            )

            $splatCheckConstraint = @{
                SqlInstance = $TestConfig.instance2
                Database    = $dbname
                Object      = $tableName
                Confirm     = $false
            }
            $result = Invoke-DbaDbDbccCheckConstraint @splatCheckConstraint
        }

        foreach ($prop in $props) {
            It "Should return property: $prop" {
                $p = $result[0].PSObject.Properties[$prop]
                $p.Name | Should -Be $prop
            }
        }

        It "Returns correct results" {
            $result.Database -match $dbname | Should -Be $true
            $result.Table -match $tableName | Should -Be $true
            $result.Constraint -match $check1 | Should -Be $true
            $result.Output.Substring(0, 25) -eq "DBCC execution completed." | Should -Be $true
        }
    }
}