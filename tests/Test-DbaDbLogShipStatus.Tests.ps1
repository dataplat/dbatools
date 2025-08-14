#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-DbaDbLogShipStatus",
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
                "ExcludeDatabase",
                "Simple",
                "Primary",
                "Secondary",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When testing SQL instance edition support" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $skip = $false
            if ($server.Edition -notmatch 'Express') {
                $skip = $true
            }
        }

        It -Skip:$skip "Should warn if SQL instance edition is not supported" {
            $null = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.instance1 -WarningAction SilentlyContinue -WarningVariable editionwarn
            $editionwarn -match "Express" | Should -BeTrue
        }
    }

    Context "When no log shipping is configured" {
        It "Should warn if no log shipping found" {
            $null = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.instance2 -Database 'master' -WarningAction SilentlyContinue -WarningVariable doesntexist
            $doesntexist -match "No information available" | Should -BeTrue
        }
    }
}
