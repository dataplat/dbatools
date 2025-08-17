#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentAlertCategory",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "New Agent Alert Category is changed properly" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create test categories that we can remove later
            $testCategories = @("CategoryTest1", "CategoryTest2", "CategoryTest3")
            $randomCategoryName = "dbatoolsci_test_$(Get-Random)"

            # Create the alert categories for testing
            $null = New-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $testCategories

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any remaining test categories
            $remainingCategories = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $testCategories, $randomCategoryName -ErrorAction SilentlyContinue
            if ($remainingCategories) {
                $null = Remove-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $remainingCategories.Name -Confirm:$false
            }

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }

        It "Should have the right name" {
            $results = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $testCategories
            $results[0].Name | Should -Be "CategoryTest1"
            $results[1].Name | Should -Be "CategoryTest2"
            $results[2].Name | Should -Be "CategoryTest3"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $testCategories
            $newresults.Count | Should -Be 3
        }

        It "Remove the alert categories" {
            Remove-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $testCategories -Confirm:$false

            $newresults = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $testCategories

            $newresults.Count | Should -Be 0
        }

        It "supports piping SQL Agent alert category" {
            $categoryName = "dbatoolsci_test_$(Get-Random)"
            $null = New-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $categoryName
            (Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $categoryName) | Should -Not -BeNullOrEmpty
            Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $categoryName | Remove-DbaAgentAlertCategory -Confirm:$false
            (Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category $categoryName) | Should -BeNullOrEmpty
        }
    }
}