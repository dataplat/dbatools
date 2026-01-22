#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbTrigger",
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
        $serverInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $serverInstance.Query("$createTrigger")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $serverInstance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $dropTrigger = "DROP TRIGGER dbatoolsci_safety ON DATABASE;"
        $serverInstance.Query("$dropTrigger")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets Database Trigger" {
        BeforeAll {
            $allResults = Get-DbaDbTrigger -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -eq "dbatoolsci_safety"
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
            $databaseResults = Get-DbaDbTrigger -SqlInstance $TestConfig.InstanceSingle -Database Master
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
            $excludeResults = Get-DbaDbTrigger -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase Master
        }

        It "Gets no results" {
            $excludeResults | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbTrigger -SqlInstance $TestConfig.InstanceSingle -Database Master -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.DatabaseDdlTrigger]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'IsEnabled',
                'DateLastModified'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}