#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbQueryStoreOption",
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

        $serverSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When a system database is named explicitly" {
        It "Warns about master and tempdb instead of silently returning nothing" {
            $resultsSystemDb = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database master, tempdb -WarningVariable warnSystemDb
            $resultsSystemDb | Should -BeNullOrEmpty
            $warnSystemDb -join "`n" | Should -Match "Query Store cannot be enabled on system database master"
            $warnSystemDb -join "`n" | Should -Match "Query Store cannot be enabled on system database tempdb"
        }

        It "Reads model from SQL Server 2022 on and warns about it before that" {
            $resultsModel = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database model -WarningVariable warnModel

            if ($serverSingle.VersionMajor -ge 16) {
                $resultsModel.Database | Should -Be "model"
                $warnModel | Should -BeNullOrEmpty
            } else {
                $resultsModel | Should -BeNullOrEmpty
                $warnModel -join "`n" | Should -Match "Query Store cannot be read on model before SQL Server 2022"
            }
        }
    }

    Context "When no database is named" {
        It "Keeps model out of the sweep so instance defaults are never changed by accident" {
            $resultsSweep = Get-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -WarningVariable warnSweep
            $resultsSweep.Database | Should -Not -Contain "model"
            $warnSweep | Should -BeNullOrEmpty
        }
    }
}