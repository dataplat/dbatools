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
    Context "Command functions as expected" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbname = "dbatoolsci_clonetest"
            $clonedb = "dbatoolsci_clonetest_CLONE"
            $clonedb2 = "dbatoolsci_clonetest_CLONE2"

            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Query("CREATE DATABASE $dbname")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Get-DbaDatabase -SqlInstance $server -Database $dbname, $clonedb, $clonedb2 | Remove-DbaDatabase -Confirm:$false
        }

        It "warns if SQL instance version is not supported" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance1 -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue -WarningVariable versionwarn
            $versionwarn = $versionwarn | Out-String
            $versionwarn -match "required" | Should -BeTrue
        }

        It "warns if destination database already exists" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance2 -Database $dbname -CloneDatabase tempdb -WarningAction SilentlyContinue -WarningVariable dbwarn
            $dbwarn = $dbwarn | Out-String
            $dbwarn -match "exists" | Should -BeTrue
        }

        It "warns if a system db is specified to clone" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance2 -Database master -CloneDatabase $clonedb -WarningAction SilentlyContinue -WarningVariable systemwarn
            $systemwarn = $systemwarn | Out-String
            $systemwarn -match "user database" | Should -BeTrue
        }

        Context "When cloning a database" {
            BeforeAll {
                $results = Invoke-DbaDbClone -SqlInstance $TestConfig.instance2 -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue
            }

            It "returns 1 result" {
                ($results).Count | Should -BeExactly 1
            }

            It "returns a rich database object with the correct name" {
                foreach ($result in $results) {
                    $result.Name | Should -Be $clonedb
                }
            }
        }
    }
}

