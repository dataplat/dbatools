#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaProductKey",
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
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets ProductKey for Instances on $($env:ComputerName)" {
        BeforeAll {
            # Add error handling to see what's actually happening
            try {
                $script:results = @(Get-DbaProductKey -ComputerName $env:ComputerName -EnableException)
                Write-Host "Got $($script:results.Count) results" -ForegroundColor Yellow
            }
            catch {
                Write-Host "Error in BeforeAll: $($_.Exception.Message)" -ForegroundColor Red
                $script:results = @()
            }
        }

        It "Gets results" {
            $script:results | Should -Not -BeNullOrEmpty
        }

        It "Should have Version property" {
            foreach ($row in $script:results) {
                $row.Version | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have Edition property" {
            foreach ($row in $script:results) {
                $row.Edition | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have Key property" {
            foreach ($row in $script:results) {
                $row.key | Should -Not -BeNullOrEmpty
            }
        }
    }
}