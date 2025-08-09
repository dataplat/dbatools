#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbCompatibility",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
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
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $compatibilityLevel = $server.Databases["master"].CompatibilityLevel
    }

    Context "Gets compatibility for multiple databases" {
        BeforeAll {
            $results = Get-DbaDbCompatibility -SqlInstance $TestConfig.instance1
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return correct compatibility level for system databases" {
            foreach ($row in $results) {
                # Only test system databases as there might be leftover databases from other tests
                if ($row.DatabaseId -le 4) {
                    $row.Compatibility | Should -Be $compatibilityLevel
                }
                $dbId = (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $row.Database).Id
                $row.DatabaseId | Should -Be $dbId
            }
        }
    }

    Context "Gets compatibility for one database" {
        BeforeAll {
            $results = Get-DbaDbCompatibility -SqlInstance $TestConfig.instance1 -Database master
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return correct compatibility level for master database" {
            $results.Compatibility | Should -Be $compatibilityLevel
            $masterDbId = (Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database master).Id
            $results.DatabaseId | Should -Be $masterDbId
        }
    }
}
