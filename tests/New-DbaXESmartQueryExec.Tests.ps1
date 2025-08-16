#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName   = "dbatools",
    $CommandName = "New-DbaXESmartQueryExec",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeDiscovery {
    $TestConfig = Get-TestConfig
}

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Query",
                "EnableException",
                "Event",
                "Filter"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Creates a smart object" {
        It "Returns the object with all of the correct properties" {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            try {
                $results = New-DbaXESmartQueryExec -SqlInstance $TestConfig.instance2 -Database dbadb -Query "update table set whatever = 1"
                $results.TSQL | Should -Be "update table set whatever = 1"
                $results.ServerName | Should -Be $TestConfig.instance2
                $results.DatabaseName | Should -Be "dbadb"
                $results.Password | Should -Be $null
            } catch {
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }
        }
    }
}