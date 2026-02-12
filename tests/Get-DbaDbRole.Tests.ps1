#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbRole",
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
                "ExcludeRole",
                "ExcludeFixedRole",
                "InputObject",
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

        $instance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $allDatabases = $instance.Databases

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Functionality" {
        It "Returns Results" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle

            $result.Count | Should -BeGreaterThan $allDatabases.Count
        }

        It "Includes Fixed Roles" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle

            $result.IsFixedRole | Select-Object -Unique | Should -Contain $true
        }

        It "Returns all role membership for all databases" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly $allDatabases.Count
        }

        It "Accepts a list of databases" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database "msdb"

            $result.Database | Select-Object -Unique | Should -Be "msdb"
        }

        It "Excludes databases" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase "msdb"

            $uniqueDatabases = $result.Database | Select-Object -Unique
            $uniqueDatabases.Count | Should -BeExactly ($allDatabases.Count - 1)
            $uniqueDatabases | Should -Not -Contain "msdb"
        }

        It "Accepts a list of roles" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Role "db_owner"

            $result.Name | Select-Object -Unique | Should -Be "db_owner"
        }

        It "Excludes roles" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -ExcludeRole "db_owner"

            $result.Name | Select-Object -Unique | Should -Not -Contain "db_owner"
        }

        It "Excludes fixed roles" {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -ExcludeFixedRole

            $result.IsFixedRole | Should -Not -Contain $true
            $result.Name | Select-Object -Unique | Should -Not -Contain "db_owner"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaDbRole -SqlInstance $TestConfig.InstanceSingle -Database master -Role "db_owner"
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.DatabaseRole"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "Database",
                "Name",
                "IsFixedRole"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}