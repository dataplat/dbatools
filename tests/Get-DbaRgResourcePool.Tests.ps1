#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRgResourcePool",
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
                "Type",
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
    Context "When getting resource pools" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $allResults = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets Results" {
            $allResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "When getting resource pools using -Type parameter" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $typeResults = Get-DbaRgResourcePool -SqlInstance $TestConfig.instance2 -Type Internal
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets Results with Type filter" {
            $typeResults | Should -Not -BeNullOrEmpty
        }
    }
}