#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbTrigger",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

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
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        #trigger adapted from https://docs.microsoft.com/en-us/sql/t-sql/statements/create-trigger-transact-sql?view=sql-server-2017
        $createTrigger = @"
CREATE TRIGGER dbatoolsci_safety
    ON DATABASE
    FOR DROP_SYNONYM
    AS
    IF (@@ROWCOUNT = 0)
    RETURN;
    RAISERROR ('You must disable Trigger "dbatoolsci_safety" to drop synonyms!',10, 1)
    ROLLBACK
"@
        $serverInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $serverInstance.Query("$createTrigger")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }


    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $serverInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $dropTrigger = "DROP TRIGGER dbatoolsci_safety ON DATABASE;"
        $serverInstance.Query("$dropTrigger")
    }

    Context "Gets Database Trigger" {
        BeforeAll {
            $allResults = Get-DbaDbTrigger -SqlInstance $TestConfig.instance2 | Where-Object Name -eq "dbatoolsci_safety"
        }

        It "Gets results" {
            $allResults | Should -Not -BeNullOrEmpty
        }


        It "Should be enabled" {
            $allResults.IsEnabled | Should -Be $true
        }


        It "Should have text of Trigger" {
            $allResults.Text | Should -BeLike "*FOR DROP_SYNONYM*"
        }
    }


    Context "Gets Database Trigger when using -Database" {
        BeforeAll {
            $databaseResults = Get-DbaDbTrigger -SqlInstance $TestConfig.instance2 -Database Master
        }

        It "Gets results" {
            $databaseResults | Should -Not -BeNullOrEmpty
        }


        It "Should be enabled" {
            $databaseResults.IsEnabled | Should -Be $true
        }


        It "Should have text of Trigger" {
            $databaseResults.Text | Should -BeLike "*FOR DROP_SYNONYM*"
        }
    }


    Context "Gets no Database Trigger when using -ExcludeDatabase" {
        BeforeAll {
            $excludeResults = Get-DbaDbTrigger -SqlInstance $TestConfig.instance2 -ExcludeDatabase Master
        }

        It "Gets no results" {
            $excludeResults | Should -BeNullOrEmpty
        }
    }
}