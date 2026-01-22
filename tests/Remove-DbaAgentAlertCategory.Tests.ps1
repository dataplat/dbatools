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
            $null = New-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategories

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any remaining test categories
            $remainingCategories = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategories, $randomCategoryName -ErrorAction SilentlyContinue
            if ($remainingCategories) {
                $null = Remove-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $remainingCategories.Name
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have the right name" {
            $results = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategories
            $results[0].Name | Should -Be "CategoryTest1"
            $results[1].Name | Should -Be "CategoryTest2"
            $results[2].Name | Should -Be "CategoryTest3"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategories
            $newresults.Count | Should -Be 3
        }

        It "Remove the alert categories" {
            Remove-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategories

            $newresults = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategories

            $newresults.Count | Should -Be 0
        }

        It "supports piping SQL Agent alert category" {
            $categoryName = "dbatoolsci_test_$(Get-Random)"
            $null = New-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $categoryName
            (Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $categoryName) | Should -Not -BeNullOrEmpty
            Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $categoryName | Remove-DbaAgentAlertCategory
            (Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $categoryName) | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create test category that we can remove
            $testOutputCategory = "dbatoolsci_output_test_$(Get-Random)"
            $null = New-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $testOutputCategory

            # Remove the category to get output
            $result = Remove-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category $testOutputCategory

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'Status',
                'IsRemoved'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has IsRemoved set to true for successful removal" {
            $result.IsRemoved | Should -Be $true
        }

        It "Has Status set to 'Dropped' for successful removal" {
            $result.Status | Should -Be "Dropped"
        }
    }
}