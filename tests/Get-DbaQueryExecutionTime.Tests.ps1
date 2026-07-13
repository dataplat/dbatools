#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaQueryExecutionTime",
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
                "MaxResultsPerDb",
                "MinExecs",
                "MinExecMs",
                "ExcludeSystem",
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

        $splatFixture = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = "tempdb"
        }
        $null = Invoke-DbaQuery @splatFixture -Query "CREATE OR ALTER PROCEDURE dbo.dbatoolsci_queryexectime AS SELECT 1 AS A"
        foreach ($execRun in 1..3) {
            $null = Invoke-DbaQuery @splatFixture -Query "EXEC dbo.dbatoolsci_queryexectime"
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query "DROP PROCEDURE dbo.dbatoolsci_queryexectime" -ErrorAction SilentlyContinue
    }

    Context "When retrieving query execution times" {
        It "Returns the fixture procedure with the expected shape" {
            $splatQuery = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "tempdb"
                MinExecs        = 2
                MinExecMs       = 0
                MaxResultsPerDb = 5000
            }
            $results = @(Get-DbaQueryExecutionTime @splatQuery)
            $fixture = @($results | Where-Object ProcName -eq "dbatoolsci_queryexectime")
            $fixture | Should -Not -BeNullOrEmpty
            $fixture[0].Database | Should -Be "tempdb"
            $fixture[0].Executions | Should -BeGreaterOrEqual 2
        }
    }
}