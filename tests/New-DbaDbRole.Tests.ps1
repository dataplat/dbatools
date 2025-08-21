#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbRole",
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
                "Role",
                "Owner",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $instance = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $dbname = "dbatoolsci_adddb_newrole"
        $instance.Query("create database $dbname")
        $roleExecutor = "dbExecuter"
        $roleSPAccess = "dbSPAccess"
        $owner = 'dbo'

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterEach {
        $null = Remove-DbaDbRole -SqlInstance $instance -Database $dbname -Role $roleExecutor, $roleSPAccess
    }
    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $instance -Database $dbname

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        It 'Add new role and returns results' {
            $result = New-DbaDbRole -SqlInstance $instance -Database $dbname -Role $roleExecutor

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
            $result.Parent | Should -Be $dbname
        }

        It 'Add new role with specificied owner' {
            $result = New-DbaDbRole -SqlInstance $instance -Database $dbname -Role $roleExecutor -Owner $owner

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
            $result.Owner | Should -Be $owner
            $result.Parent | Should -Be $dbname
        }

        It 'Add two new roles and returns results' {
            $result = New-DbaDbRole -SqlInstance $instance -Database $dbname -Role $roleExecutor, $roleSPAccess

            $result.Count | Should -Be 2
            $result.Name | Should -Contain $roleExecutor
            $result.Name | Should -Contain $roleSPAccess
            $result.Parent | Select-Object -Unique | Should -Be $dbname
        }

        It 'Accept database as inputObject' {
            $result = $instance.Databases[$dbname] | New-DbaDbRole -Role $roleExecutor

            $result.Count | Should -Be 1
            $result.Name | Should -Be $roleExecutor
            $result.Parent | Should -Be $dbname
        }
    }
}