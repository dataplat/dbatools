#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaAgentJobCategory",
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
                "NewName",
                "Force",
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

            # Create test category for modification
            $testCategoryName = "CategoryTest1"
            $newCategoryName = "CategoryTest2"
            $testCategory = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategoryName

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup and ignore all output
            Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $newCategoryName -ErrorAction SilentlyContinue
            Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategoryName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have the right name and category type" {
            $testCategory.Name | Should -Be "CategoryTest1"
            $testCategory.CategoryType | Should -Be "LocalJob"
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category CategoryTest1
            $newresults.Name | Should -Be "CategoryTest1"
            $newresults.CategoryType | Should -Be "LocalJob"
        }

        It "Change the name of the job category" {
            $results = Set-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category CategoryTest1 -NewName CategoryTest2
            $results.Name | Should -Be "CategoryTest2"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputCategoryName = "dbatoolsci_outputtest_cat_$(Get-Random)"
            $outputCategoryNewName = "dbatoolsci_outputtest_cat2_$(Get-Random)"
            $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $outputCategoryName
            $result = Set-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $outputCategoryName -NewName $outputCategoryNewName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            try {
                $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $TestConfig.SqlCred
                $catToRemove = $server.JobServer.JobCategories | Where-Object Name -in $outputCategoryNewName, $outputCategoryName
                foreach ($cat in $catToRemove) {
                    $cat.Drop()
                }
            } catch {
                # Ignore cleanup errors
            }
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Agent.JobCategory"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "ID",
                "CategoryType",
                "JobCount"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}