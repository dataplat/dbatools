#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFileGrowth",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Should return file information" {
        It "returns information about msdb files" {
            $result = Get-DbaDbFileGrowth -SqlInstance $TestConfig.instance2
            $result.Database -contains "msdb" | Should -Be $true
        }
    }

    Context "Should return file information for only msdb" {
        It "returns only msdb files" {
            $result = Get-DbaDbFileGrowth -SqlInstance $TestConfig.instance2 -Database msdb | Select-Object -First 1
            $result.Database | Should -Be "msdb"
        }
    }
}