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
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create test job categories
            $testCategories = @("CategoryTest1", "CategoryTest2", "CategoryTest3")
            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategories

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clean up any remaining test categories
            $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category "CategoryTest1", "CategoryTest2", "CategoryTest3" -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have the right name and category type" {
            $results = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category "CategoryTest1", "CategoryTest2", "CategoryTest3"
            $results[0].Name | Should -Be "CategoryTest1"
            $results[0].CategoryType | Should -Be "LocalJob"
            $results[1].Name | Should -Be "CategoryTest2"
            $results[1].CategoryType | Should -Be "LocalJob"
            $results[2].Name | Should -Be "CategoryTest3"
            $results[2].CategoryType | Should -Be "LocalJob"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category "CategoryTest1", "CategoryTest2", "CategoryTest3"
            $newresults.Count | Should -Be 3
        }

        It "Remove the job categories" {
            Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category "CategoryTest1", "CategoryTest2", "CategoryTest3"

            $newresults = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category "CategoryTest1", "CategoryTest2", "CategoryTest3"

            $newresults.Count | Should -Be 0
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputCategoryName = "dbatoolsci_outputtest_$(Get-Random)"
            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $outputCategoryName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $result = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $outputCategoryName
        }

        AfterAll {
            $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $outputCategoryName -ErrorAction SilentlyContinue
        }

        It "Returns output as PSCustomObject" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Name", "Status", "IsRemoved")
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has the correct values for a successful removal" {
            $result.Name | Should -Be $outputCategoryName
            $result.Status | Should -Be "Dropped"
            $result.IsRemoved | Should -BeTrue
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}