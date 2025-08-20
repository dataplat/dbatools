#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentJobCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Category",
                "CategoryType",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "New Agent Job Category is changed properly" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            # Create test job categories
            $testCategories = @("CategoryTest1", "CategoryTest2", "CategoryTest3")
            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category $testCategories

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            # Clean up any remaining test categories
            $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "CategoryTest1", "CategoryTest2", "CategoryTest3" -Confirm:$false -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have the right name and category type" {
            $results = Get-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "CategoryTest1", "CategoryTest2", "CategoryTest3"
            $results[0].Name | Should -Be "CategoryTest1"
            $results[0].CategoryType | Should -Be "LocalJob"
            $results[1].Name | Should -Be "CategoryTest2"
            $results[1].CategoryType | Should -Be "LocalJob"
            $results[2].Name | Should -Be "CategoryTest3"
            $results[2].CategoryType | Should -Be "LocalJob"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "CategoryTest1", "CategoryTest2", "CategoryTest3"
            $newresults.Count | Should -Be 3
        }

        It "Remove the job categories" {
            Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "CategoryTest1", "CategoryTest2", "CategoryTest3" -Confirm:$false

            $newresults = Get-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "CategoryTest1", "CategoryTest2", "CategoryTest3"

            $newresults.Count | Should -Be 0
        }
    }
}