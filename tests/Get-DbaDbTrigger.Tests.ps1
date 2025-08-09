#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbTrigger",
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

        #trigger adapted from https://docs.microsoft.com/en-us/sql/t-sql/statements/create-trigger-transact-sql?view=sql-server-2017
        $trigger = @"
CREATE TRIGGER dbatoolsci_safety
    ON DATABASE
    FOR DROP_SYNONYM
    AS
    IF (@@ROWCOUNT = 0)
    RETURN;
    RAISERROR ('You must disable Trigger "dbatoolsci_safety" to drop synonyms!',10, 1)
    ROLLBACK
"@
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $server.Query("$trigger")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $trigger = "DROP TRIGGER dbatoolsci_safety ON DATABASE;"
        $server.Query("$trigger")

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Gets Database Trigger" {
        BeforeAll {
            $results = Get-DbaDbTrigger -SqlInstance $TestConfig.instance2 | Where-Object Name -eq "dbatoolsci_safety"
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be enabled" {
            $results.IsEnabled | Should -BeTrue
        }

        It "Should have text of Trigger" {
            $results.Text | Should -BeLike "*FOR DROP_SYNONYM*"
        }
    }

    Context "Gets Database Trigger when using -Database" {
        BeforeAll {
            $results = Get-DbaDbTrigger -SqlInstance $TestConfig.instance2 -Database Master
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be enabled" {
            $results.IsEnabled | Should -BeTrue
        }

        It "Should have text of Trigger" {
            $results.Text | Should -BeLike "*FOR DROP_SYNONYM*"
        }
    }

    Context "Gets no Database Trigger when using -ExcludeDatabase" {
        BeforeAll {
            $results = Get-DbaDbTrigger -SqlInstance $TestConfig.instance2 -ExcludeDatabase Master
        }

        It "Gets no results" {
            $results | Should -BeNullOrEmpty
        }
    }
}