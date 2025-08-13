#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Invoke-DbaDbClone",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "InputObject",
                "CloneDatabase",
                "ExcludeStatistics",
                "ExcludeQueryStore",
                "UpdateStatistics",
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

        # Explain what needs to be set up for the test:
        # We need a source database to clone and we'll create multiple clone databases for testing

        # Set variables. They are available in all the It blocks.
        $dbname   = "dbatoolsci_clonetest"
        $clonedb  = "dbatoolsci_clonetest_CLONE"
        $clonedb2 = "dbatoolsci_clonetest_CLONE2"

        # Create the objects.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $server.Query("CREATE DATABASE $dbname")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname, $clonedb, $clonedb2 | Remove-DbaDatabase

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Command functions as expected" {
        BeforeAll {
            # Get reference to test variables from parent scope
            $testDbName   = "dbatoolsci_clonetest"
            $testCloneDb  = "dbatoolsci_clonetest_CLONE"
            $testCloneDb2 = "dbatoolsci_clonetest_CLONE2"
        }

        It "warns if SQL instance version is not supported" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance1 -Database $testDbName -CloneDatabase $testCloneDb -WarningAction SilentlyContinue -WarningVariable versionwarn
            $versionwarn = $versionwarn | Out-String
            $versionwarn -match "required" | Should -BeTrue
        }

        It "warns if destination database already exists" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance2 -Database $testDbName -CloneDatabase tempdb -WarningAction SilentlyContinue -WarningVariable dbwarn
            $dbwarn = $dbwarn | Out-String
            $dbwarn -match "exists" | Should -BeTrue
        }

        It "warns if a system db is specified to clone" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance2 -Database master -CloneDatabase $testCloneDb -WarningAction SilentlyContinue -WarningVariable systemwarn
            $systemwarn = $systemwarn | Out-String
            $systemwarn -match "user database" | Should -BeTrue
        }

        It "returns 1 result" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance2 -Database $testDbName -CloneDatabase $testCloneDb -WarningAction SilentlyContinue
            $results.Count | Should -BeExactly 1
        }

        It "returns a rich database object with the correct name" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance2 -Database $testDbName -CloneDatabase $testCloneDb2 -WarningAction SilentlyContinue
            $results.Name | Should -BeIn $testCloneDb, $testCloneDb2
        }
    }
}

