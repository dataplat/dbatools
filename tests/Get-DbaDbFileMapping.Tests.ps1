#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFileMapping",
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
        It "returns information about multiple databases" {
            $results = Get-DbaDbFileMapping -SqlInstance $TestConfig.instance1
            $results.Database -contains "tempdb" | Should -Be $true
            $results.Database -contains "master" | Should -Be $true
        }
    }

    Context "Should return file information for a single database" {
        It "returns information about tempdb" {
            $results = Get-DbaDbFileMapping -SqlInstance $TestConfig.instance1 -Database tempdb
            $results.Database -contains "tempdb" | Should -Be $true
            $results.Database -contains "master" | Should -Be $false
        }
    }
}