#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbUserDefinedTableType",
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
                "EnableException",
                "Database",
                "ExcludeDatabase",
                "Type"
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $tableTypeName = "dbatools_$(Get-Random)"
        $tableTypeName1 = "dbatools_$(Get-Random)"
        $server.Query("CREATE TYPE $tableTypeName AS TABLE([column1] INT NULL)", "tempdb")
        $server.Query("CREATE TYPE $tableTypeName1 AS TABLE([column1] INT NULL)", "tempdb")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("DROP TYPE $tableTypeName", "tempdb")
        $null = $server.Query("DROP TYPE $tableTypeName1", "tempdb")

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Gets a Db User Defined Table Type" {
        BeforeAll {
            $splatUserDefinedTableType = @{
                SqlInstance = $TestConfig.instance2
                Database    = "tempdb"
                Type        = $tableTypeName
            }
            $results = Get-DbaDbUserDefinedTableType @splatUserDefinedTableType
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a name of $tableTypeName" {
            $results.Name | Should -BeExactly $tableTypeName
        }

        It "Should have an owner of dbo" {
            $results.Owner | Should -BeExactly "dbo"
        }

        It "Should have a count of 1" {
            $results.Status.Count | Should -BeExactly 1
        }
    }

    Context "Gets all the Db User Defined Table Types" {
        BeforeAll {
            $results = Get-DbaDbUserDefinedTableType -SqlInstance $TestConfig.instance2 -Database "tempdb"
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a count of 2" {
            $results.Status.Count | Should -BeExactly 2
        }
    }
}