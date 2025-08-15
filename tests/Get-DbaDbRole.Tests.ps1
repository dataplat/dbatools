#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbRole",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Role",
                "ExcludeRole",
                "ExcludeFixedRole",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $instance = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $allDatabases = $instance.Databases

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    Context "Functionality" {
        It "Returns Results" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2

            $result.Count | Should -BeGreaterThan $allDatabases.Count
        }

        It "Includes Fixed Roles" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2

            $result.IsFixedRole | Select-Object -Unique | Should -Contain $true
        }

        It "Returns all role membership for all databases" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly $allDatabases.Count
        }

        It "Accepts a list of databases" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Database "msdb"

            $result.Database | Select-Object -Unique | Should -Be "msdb"
        }

        It "Excludes databases" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -ExcludeDatabase "msdb"

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly ($allDatabases.Count - 1)
            $uniqueDatabases | Should -Not -Contain "msdb"
        }

        It "Accepts a list of roles" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -Role "db_owner"

            $result.Name | Select-Object -Unique | Should -Be "db_owner"
        }

        It "Excludes roles" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -ExcludeRole "db_owner"

            $result.Name | Select-Object -Unique | Should -Not -Contain "db_owner"
        }

        It "Excludes fixed roles" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.instance2 -ExcludeFixedRole

            $result.IsFixedRole | Should -Not -Contain $true
            $result.Name | Select-Object -Unique | Should -Not -Contain "db_owner"
        }
    }
}