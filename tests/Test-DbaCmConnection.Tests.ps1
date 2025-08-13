#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-DbaCmConnection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = @(
                "ComputerName",
                "Credential",
                "Type",
                "Force",
                "EnableException"
            )
            $expectedParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        }

        It "Should have the expected parameters" {
            $comparison = Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters
            @($comparison).Count | Should -Be 0
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When testing connection" {
        BeforeAll {
            $splatConnection = @{
                Type = "Wmi"
            }
            $testResults = Test-DbaCmConnection @splatConnection
        }

        It "Should return valid connection info" {
            $testResults | Should -Not -BeNullOrEmpty
            $testResults.ComputerName | Should -Be $env:COMPUTERNAME
            $testResults.Available | Should -BeOfType [bool]
        }
    }
}