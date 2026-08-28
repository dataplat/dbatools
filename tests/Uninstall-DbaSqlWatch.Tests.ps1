#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Uninstall-DbaSqlWatch",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5 -or $env:appveyor) {
    # Skip IntegrationTests on AppVeyor because they take too long and skip on pwsh because the command is not supported.

    # The SqlWatch dacpac contains a case insensitive model and DacFx refuses to deploy that to a case sensitive
    # target (error SQL72030), so there is nothing to uninstall there and the Context below skips, which also keeps
    # the BeforeAll from installing. We ask the instance for the behaviour instead of matching the collation name,
    # because _BIN and _BIN2 collations are case sensitive too and carry no _CS_. A failed probe leaves the skip off
    # so a real connection problem still fails the tests loudly.
    $sqlWatchInstanceIsCaseSensitive = $false
    try {
        $sqlWatchCaseQuery = "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.databases WHERE name = UPPER(DB_NAME(1))) THEN 0 ELSE 1 END AS IsCaseSensitive"
        $sqlWatchInstanceIsCaseSensitive = (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $sqlWatchCaseQuery -EnableException).IsCaseSensitive -eq 1
    } catch {
        $sqlWatchInstanceIsCaseSensitive = $false
    }

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $database = "dbatoolsci_sqlwatch_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Query("CREATE DATABASE $database")
        Install-DbaSqlWatch -SqlInstance $TestConfig.InstanceSingle -Database $database

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Testing SqlWatch uninstaller" -Skip:$sqlWatchInstanceIsCaseSensitive {
        BeforeAll {
            $null = Uninstall-DbaSqlWatch -SqlInstance $TestConfig.InstanceSingle -Database $database
        }

        It "Removed all tables" {
            $tableCount = (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $Database | Where-Object { ($PSItem.Name -like "sql_perf_mon_*") -or ($PSItem.Name -like "logger_*") }).Count
            $tableCount | Should -Be 0
        }

        It "Removed all views" {
            $viewCount = (Get-DbaDbView -SqlInstance $TestConfig.InstanceSingle -Database $Database | Where-Object { $PSItem.Name -like "vw_sql_perf_mon_*" }).Count
            $viewCount | Should -Be 0
        }

        It "Removed all stored procedures" {
            $sprocCount = (Get-DbaDbStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $Database | Where-Object { ($PSItem.Name -like "sp_sql_perf_mon_*") -or ($PSItem.Name -like "usp_logger_*") }).Count
            $sprocCount | Should -Be 0
        }

        It "Removed all SQL Agent jobs" {
            $agentCount = (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle | Where-Object { ($PSItem.Name -like "SqlWatch-*") -or ($PSItem.Name -like "DBA-PERF-*") }).Count
            $agentCount | Should -Be 0
        }
    }
}