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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $tableTypeName = "dbatools_$(Get-Random)"
        $tableTypeName1 = "dbatools_$(Get-Random)"
        $server.Query("CREATE TYPE $tableTypeName AS TABLE([column1] INT NULL)", "tempdb")
        $server.Query("CREATE TYPE $tableTypeName1 AS TABLE([column1] INT NULL)", "tempdb")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $server.Query("DROP TYPE $tabletypename", "tempdb") -ErrorAction SilentlyContinue
        $null = $server.Query("DROP TYPE $tabletypename1", "tempdb") -ErrorAction SilentlyContinue
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
            $results.Count | Should -BeExactly 1
        }
    }

    Context "Gets all the Db User Defined Table Type" {
        BeforeAll {
            $results = Get-DbaDbUserDefinedTableType -SqlInstance $TestConfig.instance2 -Database tempdb
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a count of 2" {
            $results.Count | Should -BeExactly 2
        }
    }
}