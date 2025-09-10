#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaSqlWatch",
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
                "LocalFile",
                "Force",
                "PreRelease",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5 -or $env:appveyor) {
    # Skip IntegrationTests on AppVeyor because they take too long and skip on pwsh because the command is not supported.

    Context "Testing SqlWatch installer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $database = "dbatoolsci_sqlwatch_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Query("CREATE DATABASE $database")

            $results = Install-DbaSqlWatch -SqlInstance $TestConfig.instance2 -Database $database

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Uninstall-DbaSqlWatch -SqlInstance $TestConfig.instance2 -Database $database -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $database -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $database" {
            $results[0].Database -eq $database | Should -Be $true
        }
        It "Returns an object with the expected properties" {
            $result = $results[0]
            $ExpectedProps = "SqlInstance", "InstanceName", "ComputerName", "Database", "Status", "DashboardPath"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
        It "Installed tables" {
            $tableCount = (Get-DbaDbTable -SqlInstance $TestConfig.instance2 -Database $database | Where-Object Name -like "sqlwatch_*").Count
            $tableCount | Should -BeGreaterThan 0
        }
        It "Installed views" {
            $viewCount = (Get-DbaDbView -SqlInstance $TestConfig.instance2 -Database $database | Where-Object Name -like "vw_sqlwatch_*").Count
            $viewCount | Should -BeGreaterThan 0
        }
        It "Installed stored procedures" {
            $sprocCount = (Get-DbaDbStoredProcedure -SqlInstance $TestConfig.instance2 -Database $database | Where-Object Name -like "usp_sqlwatch_*").Count
            $sprocCount | Should -BeGreaterThan 0
        }
        It "Installed SQL Agent jobs" {
            $agentCount = (Get-DbaAgentJob -SqlInstance $TestConfig.instance2 | Where-Object { ($PSItem.Name -like "SqlWatch-*") -or ($PSItem.Name -like "DBA-PERF-*") }).Count
            $agentCount | Should -BeGreaterThan 0
        }

    }
}