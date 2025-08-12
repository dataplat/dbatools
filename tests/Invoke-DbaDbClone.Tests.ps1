#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $dbname = "dbatoolsci_clonetest"
        $clonedb = "dbatoolsci_clonetest_CLONE"
        $clonedb2 = "dbatoolsci_clonetest_CLONE2"

        # Create the test database.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $server.Query("CREATE DATABASE $dbname")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created databases.
        Get-DbaDatabase -SqlInstance $server -Database $dbname, $clonedb, $clonedb2 | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Command functions as expected" {
        It "warns if SQL instance version is not supported" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance1 -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue -WarningVariable versionwarn
            $versionwarn = $versionwarn | Out-String
            $versionwarn -match "required" | Should -Be $true
        }

        It "warns if destination database already exists" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance2 -Database $dbname -CloneDatabase tempdb -WarningAction SilentlyContinue -WarningVariable dbwarn
            $dbwarn = $dbwarn | Out-String
            $dbwarn -match "exists" | Should -Be $true
        }

        It "warns if a system db is specified to clone" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance2 -Database master -CloneDatabase $clonedb -WarningAction SilentlyContinue -WarningVariable systemwarn
            $systemwarn = $systemwarn | Out-String
            $systemwarn -match "user database" | Should -Be $true
        }

        It "creates a clone database successfully" {
            $results = @(Invoke-DbaDbClone -SqlInstance $TestConfig.instance2 -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue)
            $results.Status.Count | Should -BeExactly 1
            $results[0].Name | Should -BeIn $clonedb, $clonedb2
        }
    }
}