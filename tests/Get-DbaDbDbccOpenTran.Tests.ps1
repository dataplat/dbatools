#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbDbccOpenTran",
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
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets results for Open Transactions" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Cmd",
                "Output",
                "Field",
                "Data"
            )
        }

        It "returns results for DBCC OPENTRAN" {
            $result = Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.instance1
            $result | Should -Not -BeNullOrEmpty
        }

        It "returns multiple results" {
            $result = Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.instance1
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should return all expected properties" {
            $result = Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.instance1
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }

        It "returns results for a specific database" {
            $result = Get-DbaDbDbccOpenTran -SqlInstance $TestConfig.instance1 -Database tempDB
            $tempDB = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database tempDB
            
            $result | Should -Not -BeNullOrEmpty
            $result.Database | Get-Unique | Should -Be "tempDB"
            $result.DatabaseId | Get-Unique | Should -Be $tempDB.Id
        }
    }
}