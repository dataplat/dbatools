#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-PSRemoting",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
. "$PSScriptRoot\..\private\functions\Test-PSRemoting.ps1"

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Returns a boolean with no exceptions" {
        BeforeAll {
            $failResult = Test-PSRemoting -ComputerName "funny"
            $successResult = Test-PSRemoting -ComputerName localhost
        }

        It "Returns false when failing" {
            $failResult | Should -Be $false
        }

        It "Returns true when succeeding" {
            $successResult | Should -Be $true
        }
    }

    Context "Handles an instance, using just the computername" {
        It "Returns true when succeeding" {
            $instanceResult = Test-PSRemoting -ComputerName $TestConfig.instance1
            $instanceResult | Should -Be $true
        }
    }
}