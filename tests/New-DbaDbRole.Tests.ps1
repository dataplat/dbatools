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

        $instance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
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

    Context "Output validation" {
        BeforeAll {
            $outputDbName = "dbatoolsci_outputrole"
            $outputInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $outputInstance.Query("IF DB_ID('$outputDbName') IS NULL CREATE DATABASE [$outputDbName]")
            $outputRole = New-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database $outputDbName -Role "dbatoolsci_outputtest"
        }
        AfterAll {
            $outputInstance.Query("IF DB_ID('$outputDbName') IS NOT NULL DROP DATABASE [$outputDbName]")
        }

        It "Returns output of the documented type" {
            $outputRole | Should -Not -BeNullOrEmpty
            $outputRole[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.DatabaseRole"
        }

        It "Has the expected default display properties" {
            $defaultProps = $outputRole[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Name", "Parent", "Owner")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            $outputRole[0].psobject.Properties["Parent"] | Should -Not -BeNullOrEmpty
            $outputRole[0].psobject.Properties["Parent"].MemberType | Should -Be "AliasProperty"
        }
    }
}