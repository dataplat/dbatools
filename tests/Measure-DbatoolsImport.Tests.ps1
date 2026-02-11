#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Measure-DbatoolsImport",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It -Skip "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $result = Measure-DbatoolsImport
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $result[0].PSObject.Properties.Name | Should -Contain "Action"
            $result[0].PSObject.Properties.Name | Should -Contain "Duration"
        }

        It "Has non-empty Action values" {
            $result[0].Action | Should -Not -BeNullOrEmpty
        }

        It "Has Duration values that are not zero" {
            $result[0].Duration | Should -Not -Be "00:00:00"
        }
    }
}