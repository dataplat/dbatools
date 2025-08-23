#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaStartupProcedure",
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
                "StartupProcedure",
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

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When retrieving all startup procedures" {
        It "Returns correct results" {
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.instance2
            $result.Schema -eq "dbo" | Should -Be $true
            $result.Name -eq "StartUpProc$random" | Should -Be $true
        }
    }

    Context "When filtering by StartupProcedure parameter" {
        It "Returns correct results" {
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.instance2 -StartupProcedure $startupProc
            $result.Schema -eq "dbo" | Should -Be $true
            $result.Name -eq "StartUpProc$random" | Should -Be $true
        }
    }

    Context "When filtering by incorrect StartupProcedure parameter" {
        It "Returns no results" {
            $result = Get-DbaStartupProcedure -SqlInstance $TestConfig.instance2 -StartupProcedure "Not.Here"
            $null -eq $result | Should -Be $true
        }
    }
}