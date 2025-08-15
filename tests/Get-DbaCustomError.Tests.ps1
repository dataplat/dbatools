#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaCustomError",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Validate parameters" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
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

        # Explain what needs to be set up for the test:
        # We need to create a custom error message to test retrieval.

        # Set variables. They are available in all the It blocks.
        $customErrorId   = 54321
        $customErrorText = "Dbatools is Awesome!"

        # Create the custom error.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $sql = "EXEC msdb.dbo.sp_addmessage $customErrorId, 9, N'$customErrorText';"
        $server.Query($sql)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $sql = "EXEC msdb.dbo.sp_dropmessage 54321;"
        $server.Query($sql)

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Gets the custom errors" {
        BeforeAll {
            $results = Get-DbaCustomError -SqlInstance $TestConfig.instance1
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have the name Custom Error Text" {
            $results.Text | Should -Be "Dbatools is Awesome!"
        }

        It "Should have a LanguageID" {
            $results.LanguageID | Should -Be 1033
        }

        It "Should have a Custom Error ID" {
            $results.ID | Should -Be 54321
        }
    }
}