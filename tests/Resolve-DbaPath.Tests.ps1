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

    Context "Output Validation" {
        BeforeAll {
            $result = Resolve-DbaPath -Path "."
        }

        It "Returns System.String type" {
            $result | Should -BeOfType [System.String]
        }

        It "Returns a fully qualified path" {
            $result | Should -Not -BeNullOrEmpty
            [System.IO.Path]::IsPathRooted($result) | Should -BeTrue
        }
    }

    Context "Output with -NewChild" {
        BeforeAll {
            $result = Resolve-DbaPath -Path ".\newfile.txt" -NewChild
        }

        It "Returns System.String for new child path" {
            $result | Should -BeOfType [System.String]
        }

        It "Returns path even if file does not exist" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "newfile\.txt$"
        }
    }

    Context "Output with multiple paths" {
        BeforeAll {
            $result = Resolve-DbaPath -Path @(".", "..")
        }

        It "Returns multiple strings when given multiple paths" {
            $result | Should -HaveCount 2
            foreach ($path in $result) {
                $path | Should -BeOfType [System.String]
            }
        }
    }
}