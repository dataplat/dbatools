#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Resolve-DbaPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Provider",
                "SingleItem",
                "NewChild"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $result = Resolve-DbaPath -Path $env:TEMP
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [System.String]
        }

        It "Returns a valid file system path" {
            Test-Path -Path $result | Should -BeTrue
        }
    }
}