#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaXESmartTableWriter",
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
                "Table",
                "AutoCreateTargetTable",
                "UploadIntervalSeconds",
                "Event",
                "OutputColumn",
                "Filter",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Creates a smart object" {
        BeforeAll {
            $splatTableWriter = @{
                SqlInstance = $TestConfig.instance2
                Database    = "planning"
            }
        }

        It "returns the object with all of the correct properties" {
            $results = New-DbaXESmartTableWriter @splatTableWriter
            $results.ServerName | Should -Be $TestConfig.instance2
            $results.DatabaseName | Should -Be "planning"
            $results.Password | Should -Be $null
            $results.DelaySeconds | Should -Be 0
        }
    }
}