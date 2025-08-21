#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaFile",
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
                "Path",
                "FileType",
                "Depth",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Returns some files" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $random = Get-Random
            $testDbName = "dbatoolsci_getfile$random"
            $server.Query("CREATE DATABASE $testDbName")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDbName | Remove-DbaDatabase -Confirm:$false

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should find the new database file" {
            $results = Get-DbaFile -SqlInstance $TestConfig.instance2
            ($results.Filename -match "dbatoolsci").Count | Should -BeGreaterThan 0
        }

        It "Should find the new database log file" {
            $logPath = (Get-DbaDefaultPath -SqlInstance $TestConfig.instance2).Log
            $results = Get-DbaFile -SqlInstance $TestConfig.instance2 -Path $logPath
            ($results.Filename -like "*dbatoolsci*ldf").Count | Should -BeGreaterThan 0
        }

        It "Should find the master database file" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $masterPath = $server.MasterDBPath
            $results = Get-DbaFile -SqlInstance $TestConfig.instance2 -Path $masterPath
            ($results.Filename -match "master.mdf").Count | Should -BeGreaterThan 0
        }
    }
}