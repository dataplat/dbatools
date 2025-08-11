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
                "Database",
                "ExcludeDatabase",
                "Type",
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
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $tableTypeName = ("dbatools_{0}" -f $(Get-Random))
        $tableTypeName1 = ("dbatools_{0}" -f $(Get-Random))
        $server.Query("CREATE TYPE $tableTypeName AS TABLE([column1] INT NULL)", "tempdb")
        $server.Query("CREATE TYPE $tableTypeName1 AS TABLE([column1] INT NULL)", "tempdb")
    }

    AfterAll {
        $null = $server.Query("DROP TYPE $tableTypeName", "tempdb")
        $null = $server.Query("DROP TYPE $tableTypeName1", "tempdb")
    }

    Context "Gets a Db User Defined Table Type" {
        BeforeAll {
            $splatSingleType = @{
                SqlInstance = $TestConfig.instance2
                Database    = "tempdb"
                Type        = $tableTypeName
            }
            $singleResults = Get-DbaDbUserDefinedTableType @splatSingleType
        }

        It "Gets results" {
            $singleResults | Should -Not -BeNullOrEmpty
        }

        It "Should have a name of $tableTypeName" {
            $singleResults.Name | Should -Be $tableTypeName
        }

        It "Should have an owner of dbo" {
            $singleResults.Owner | Should -Be "dbo"
        }

        It "Should have a count of 1" {
            $singleResults.Count | Should -Be 1
        }
    }

    Context "Gets all the Db User Defined Table Types" {
        BeforeAll {
            $splatAllTypes = @{
                SqlInstance = $TestConfig.instance2
                Database    = "tempdb"
            }
            $allResults = Get-DbaDbUserDefinedTableType @splatAllTypes
        }

        It "Gets results" {
            $allResults | Should -Not -BeNullOrEmpty
        }

        It "Should have a count of 2" {
            $allResults.Count | Should -Be 2
        }
    }
}