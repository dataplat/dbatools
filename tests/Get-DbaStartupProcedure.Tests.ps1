#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaStartupProcedure",
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
                "StartupProcedure",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $random = Get-Random
        $startupProc = "dbo.StartUpProc$random"
        $dbname = "master"

        $null = $server.Query("CREATE PROCEDURE $startupProc AS Select 1", $dbname)
        $null = $server.Query("EXEC sp_procoption N'$startupProc', 'startup', '1'", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $server.Query("DROP PROCEDURE $startupProc", $dbname)
    }

    Context "When retrieving all startup procedures" {
        BeforeAll {
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.instance2
        }

        It "Returns correct results" {
            $result.Schema -eq "dbo" | Should -Be $true
            $result.Name -eq "StartUpProc$random" | Should -Be $true
        }
    }

    Context "When filtering by StartupProcedure parameter" {
        BeforeAll {
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.instance2 -StartupProcedure $startupProc
        }

        It "Returns correct results" {
            $result.Schema -eq "dbo" | Should -Be $true
            $result.Name -eq "StartUpProc$random" | Should -Be $true
        }
    }

    Context "When filtering by incorrect StartupProcedure parameter" {
        BeforeAll {
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.instance2 -StartupProcedure "Not.Here"
        }

        It "Returns no results" {
            $null -eq $result | Should -Be $true
        }
    }
}