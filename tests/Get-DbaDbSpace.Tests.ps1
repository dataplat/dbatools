#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbSpace",
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
                "ExcludeDatabase",
                "IncludeSystemDBs",
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

        # Create test database for space testing
        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("Create Database [$dbname]")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup test database
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    #Skipping these tests as internals of Get-DbaDbSpace seems to be unreliable in CI
    Context "Gets DbSpace" {
        BeforeAll {
            $results = Get-DbaDbSpace -SqlInstance $TestConfig.instance2 | Where-Object Database -eq $dbname
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve space for test database" {
            $results[0].Database | Should -Be $dbname
            $results[0].UsedSpace | Should -Not -BeNullOrEmpty
        }

        It "Should have a physical path for test database" {
            $results[0].physicalname | Should -Not -BeNullOrEmpty
        }
    }

    #Skipping these tests as internals of Get-DbaDbSpace seems to be unreliable in CI
    Context "Gets DbSpace when using -Database" {
        BeforeAll {
            $results = Get-DbaDbSpace -SqlInstance $TestConfig.instance2 -Database $dbname
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve space for test database" {
            $results[0].Database | Should -Be $dbname
            $results[0].UsedSpace | Should -Not -BeNullOrEmpty
        }

        It "Should have a physical path for test database" {
            $results[0].physicalname | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets no DbSpace for specific database when using -ExcludeDatabase" {
        BeforeAll {
            $results = Get-DbaDbSpace -SqlInstance $TestConfig.instance2 -ExcludeDatabase $dbname
        }

        It "Gets no results" {
            $results.database | Should -Not -Contain $dbname
        }
    }
}