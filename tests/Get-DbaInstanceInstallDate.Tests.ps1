#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceInstallDate",
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
                "Credential",
                "IncludeWindows",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets SQL Server Install Date" {
        BeforeAll {
            $results = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.instance2
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets SQL Server Install Date and Windows Install Date" {
        BeforeAll {
            $results = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.instance2 -IncludeWindows
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}