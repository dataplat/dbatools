#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbDataGeneratorConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "ResetIdentity",
                "TruncateTable",
                "Rows",
                "Path",
                "Force",
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

        # Create unique temp path for this test run
        $tempConfigPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $tempConfigPath -ItemType Directory

        # Set up test database and table
        $dbNameGenerator = "dbatoolsci_generatorconfig"
        $sqlCreateTable = "CREATE TABLE [dbo].[people](
                    [FirstName] [varchar](50) NULL,
                    [LastName] [varchar](50) NULL,
                    [City] [datetime] NULL
                ) ON [PRIMARY]"
        $testDb = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbNameGenerator
        $testDb.Query($sqlCreateTable)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup database and temp directory
        Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbNameGenerator -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path $tempConfigPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Command works" {

        It "Should output a file with specific content" {
            $configResults = New-DbaDbDataGeneratorConfig -SqlInstance $TestConfig.instance1 -Database $dbNameGenerator -Path $tempConfigPath
            $configResults.Directory.Name | Should -Be (Split-Path $tempConfigPath -Leaf)

            $configResults.FullName | Should -FileContentMatch $dbNameGenerator

            $configResults.FullName | Should -FileContentMatch "FirstName"

            $configResults | Remove-Item -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}