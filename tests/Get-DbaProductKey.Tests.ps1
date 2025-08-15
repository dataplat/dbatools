#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaProductKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $script:hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $script:expectedParameters = $global:TestConfig.CommonParameters
            $script:expectedParameters += @(
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $script:expectedParameters -DifferenceObject $script:hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {

    Context "Gets ProductKey for Instances on $($env:ComputerName)" {
        BeforeAll {
            $script:results = Get-DbaProductKey -ComputerName $env:ComputerName
        }

        It "Gets results" {
            $script:results | Should -Not -Be $null
        }

        It "Should have Version for each result" {
            foreach ($row in $script:results) {
                $row.Version | Should -Not -Be $null
            }
        }

        It "Should have Edition for each result" {
            foreach ($row in $script:results) {
                $row.Edition | Should -Not -Be $null
            }
        }

        It "Should have Key for each result" {
            foreach ($row in $script:results) {
                $row.key | Should -Not -Be $null
            }
        }
    }
}