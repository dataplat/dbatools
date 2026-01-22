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
        It "Should have $rowCount rows" {
            $rowCount = 10
            $dataset = Get-DbaRandomizedDataset -Template PersonalData -Rows $rowCount
            $dataset.Count | Should -Be 10
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaRandomizedDataset -Template PersonalData -Rows 1 -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has properties dynamically defined by the template" {
            # PersonalData template should have these common properties
            $result.PSObject.Properties.Name | Should -Not -BeNullOrEmpty
        }

        It "Returns the correct number of rows" {
            $result.Count | Should -Be 1
        }
    }

    Context "Output Validation with multiple rows" {
        BeforeAll {
            $result = Get-DbaRandomizedDataset -Template PersonalData -Rows 5 -EnableException
        }

        It "Returns correct count for multiple rows" {
            $result.Count | Should -Be 5
        }

        It "Each row has properties" {
            foreach ($row in $result) {
                $row.PSObject.Properties.Name | Should -Not -BeNullOrEmpty
            }
        }
    }
}