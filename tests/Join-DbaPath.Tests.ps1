#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Join-DbaPath",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Path",
                "Child"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        It "Returns System.String type" {
            $result = Join-DbaPath -Path 'C:\temp'
            $result | Should -BeOfType [System.String]
        }

        It "Returns System.String when joining multiple path segments" {
            $result = Join-DbaPath -Path 'C:\temp' -Child 'Foo', 'Bar'
            $result | Should -BeOfType [System.String]
        }

        It "Returns a non-empty string" {
            $result = Join-DbaPath -Path 'C:\temp' -Child 'Foo'
            $result | Should -Not -BeNullOrEmpty
        }
    }
}