#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaMigrationConstraint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Database",
                "ExcludeDatabase",
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

        Get-DbaProcess -SqlInstance $TestConfig.instance1 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $global:db1 = "dbatoolsci_testMigrationConstraint"
        $global:db2 = "dbatoolsci_testMigrationConstraint_2"
        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "CREATE DATABASE $global:db1"
        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "CREATE DATABASE $global:db2"
        $needed = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $global:db1, $global:db2
        $global:setupright = $true
        if ($needed.Count -ne 2) {
            $global:setupright = $false
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance1 -Database $global:db1, $global:db2 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When setup is successful" {
        It "Should have setup correctly" {
            $global:setupright | Should -Be $true
        }
    }

    Context "Validate multiple databases" {
        It "Both databases are migratable" {
            $results = Test-DbaMigrationConstraint -Source $TestConfig.instance1 -Destination $TestConfig.instance2
            foreach ($result in $results) {
                $result.IsMigratable | Should -Be $true
            }
        }
    }

    Context "Validate single database" {
        It "Databases are migratable" {
            (Test-DbaMigrationConstraint -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -Database $global:db1).IsMigratable | Should -Be $true
        }
    }
}