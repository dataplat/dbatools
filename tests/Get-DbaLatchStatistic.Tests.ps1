#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaLatchStatistic",
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
                "Threshold",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because non-useful info from newly started sql servers.

    Context "Command returns proper info" {
        BeforeAll {
            $results = Get-DbaLatchStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100
        }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "returns a hyperlink for all results" {
            foreach ($result in $results) {
                $result.URL -match "sqlskills.com" | Should -Be $true
            }
        }
    }
}