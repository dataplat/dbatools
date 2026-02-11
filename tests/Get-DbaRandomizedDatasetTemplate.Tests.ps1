#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRandomizedDatasetTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Template",
                "Path",
                "ExcludeDefault",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns templates" {
        It "Should have at least 1 row" {
            $templates = @(Get-DbaRandomizedDatasetTemplate)
            $templates.Count | Should -BeGreaterThan 0
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = @(Get-DbaRandomizedDatasetTemplate)
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProperties = @("BaseName", "FullName")
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}