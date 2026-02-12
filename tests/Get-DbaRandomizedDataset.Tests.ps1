#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRandomizedDataset",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Template",
                "TemplateFile",
                "Rows",
                "Locale",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command generates data sets" {
        BeforeAll {
            $rowCount = 10
            $dataset = @(Get-DbaRandomizedDataset -Template PersonalData -Rows $rowCount)
        }

        It "Should have $rowCount rows" {
            $dataset.Count | Should -Be 10
        }

        It "Returns output of the expected type" {
            $dataset | Should -Not -BeNullOrEmpty
            $dataset[0] | Should -BeOfType PSCustomObject
        }

        It "Has properties defined by the PersonalData template" {
            $dataset[0].PSObject.Properties.Name.Count | Should -BeGreaterThan 0
        }
    }
}