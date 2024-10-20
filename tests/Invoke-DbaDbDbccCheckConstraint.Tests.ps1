param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbDbccCheckConstraint Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbDbccCheckConstraint
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Object",
            "AllConstraints",
            "AllErrorMessages",
            "NoInformationalMessages",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Invoke-DbaDbDbccCheckConstraint Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $random = Get-Random
        $tableName = "dbatools_CheckConstraintTbl1"
        $check1 = "chkTab1"
        $dbname = "dbatoolsci_dbccCheckConstraint$random"

        $null = $server.Query("CREATE DATABASE $dbname")
        $null = $server.Query("CREATE TABLE $tableName (Col1 int, Col2 char (30))", $dbname)
        $null = $server.Query("INSERT $tableName(Col1, Col2) VALUES (100, 'Hello')", $dbname)
        $null = $server.Query("ALTER TABLE $tableName WITH NOCHECK ADD CONSTRAINT $check1 CHECK (Col1 > 100); ", $dbname)
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Validate standard output" {
        BeforeAll {
            $result = Invoke-DbaDbDbccCheckConstraint -SqlInstance $global:instance2 -Database $dbname -Object $tableName -Confirm:$false
        }

        It "Should return correct properties" {
            $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Cmd', 'Output', 'Table', 'Constraint', 'Where'
            $result[0].PSObject.Properties.Name | Should -Be $props
        }

        It "Should return correct database name" {
            $result.Database | Should -Match $dbname
        }

        It "Should return correct table name" {
            $result.Table | Should -Match $tableName
        }

        It "Should return correct constraint name" {
            $result.Constraint | Should -Match $check1
        }

        It "Should return correct output" {
            $result.Output.Substring(0, 25) | Should -Be 'DBCC execution completed.'
        }
    }
}
