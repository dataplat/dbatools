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
        $tabletypename = ("dbatools_{0}" -f $(Get-Random))
        $tabletypename1 = ("dbatools_{0}" -f $(Get-Random))
        $server.Query("CREATE TYPE $tabletypename AS TABLE([column1] INT NULL)", 'tempdb')
        $server.Query("CREATE TYPE $tabletypename1 AS TABLE([column1] INT NULL)", 'tempdb')
    }
    AfterAll {
        $null = $server.Query("DROP TYPE $tabletypename", 'tempdb')
        $null = $server.Query("DROP TYPE $tabletypename1", 'tempdb')
    }

    Context "Gets a Db User Defined Table Type" {
        BeforeAll {
            $results = Get-DbaDbUserDefinedTableType -SqlInstance $TestConfig.instance2 -Database tempdb -Type $tabletypename
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a name of $tabletypename" {
            $results.Name | Should -Be $tabletypename
        }

        It "Should have an owner of dbo" {
            $results.Owner | Should -Be "dbo"
        }

        It "Should have a count of 1" {
            $results.Status.Count | Should -BeExactly 1
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
            $results.Status.Count | Should -BeExactly 2
        }
    }
}