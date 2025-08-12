#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbView",
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
                "ExcludeSystemView",
                "View",
                "Schema",
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $global:viewName = ("dbatoolsci_{0}" -f $(Get-Random))
        $global:viewNameWithSchema = ("dbatoolsci_{0}" -f $(Get-Random))
        $server.Query("CREATE VIEW $global:viewName AS (SELECT 1 as col1)", "tempdb")
        $server.Query("CREATE SCHEMA [someschema]", "tempdb")
        $server.Query("CREATE VIEW [someschema].$global:viewNameWithSchema AS (SELECT 1 as col1)", "tempdb")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $server.Query("DROP VIEW $global:viewName", "tempdb") -ErrorAction SilentlyContinue
        $null = $server.Query("DROP VIEW [someschema].$global:viewNameWithSchema", "tempdb") -ErrorAction SilentlyContinue
        $null = $server.Query("DROP SCHEMA [someschema]", "tempdb") -ErrorAction SilentlyContinue
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaDbView -SqlInstance $TestConfig.instance2 -Database tempdb
        }

        It "Should have standard properties" {
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance")
            ($results[0].PsObject.Properties.Name | Where-Object { $PSItem -in $expectedProps } | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should get test view: $global:viewName" {
            ($results | Where-Object Name -eq $global:viewName).Name | Should -Be $global:viewName
        }

        It "Should include system views" {
            ($results | Where-Object IsSystemObject -eq $true).Count | Should -BeGreaterThan 0
        }
    }

    Context "Exclusions work correctly" {
        It "Should contain no views from master database" {
            $results = Get-DbaDbView -SqlInstance $TestConfig.instance2 -ExcludeDatabase master
            "master" | Should -Not -BeIn $results.Database
        }

        It "Should exclude system views" {
            $results = Get-DbaDbView -SqlInstance $TestConfig.instance2 -Database master -ExcludeSystemView
            ($results | Where-Object IsSystemObject -eq $true).Count | Should -Be 0
        }
    }

    Context "Piping workings" {
        It "Should allow piping from string" {
            $results = $TestConfig.instance2 | Get-DbaDbView -Database tempdb
            ($results | Where-Object Name -eq $global:viewName).Name | Should -Be $global:viewName
        }

        It "Should allow piping from Get-DbaDatabase" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database tempdb | Get-DbaDbView
            ($results | Where-Object Name -eq $global:viewName).Name | Should -Be $global:viewName
        }
    }

    Context "Schema parameter (see #9445)" {
        It "Should return just one view with schema 'someschema'" {
            $results = $TestConfig.instance2 | Get-DbaDbView -Database tempdb -Schema "someschema"
            ($results | Where-Object Name -eq $global:viewNameWithSchema).Name | Should -Be $global:viewNameWithSchema
            ($results | Where-Object Schema -ne "someschema").Count | Should -Be 0
        }
    }
}