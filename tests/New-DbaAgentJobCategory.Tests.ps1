#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentJobCategory",
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
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $testCategory1 = "CategoryTest1"
        $testCategory2 = "CategoryTest2"
        $categoriesToCleanup = @()
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategory1, $testCategory2 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "New Agent Job Category is added properly" {
        It "Should have the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategory1
            $results.Name | Should -Be $testCategory1
            $results.CategoryType | Should -Be "LocalJob"
            $categoriesToCleanup += $testCategory1
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategory2 -CategoryType MultiServerJob
            $results.Name | Should -Be $testCategory2
            $results.CategoryType | Should -Be "MultiServerJob"
            $categoriesToCleanup += $testCategory2
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategory1, $testCategory2
            $newresults[0].Name | Should -Be $testCategory1
            $newresults[0].CategoryType | Should -Be "LocalJob"
            $newresults[1].Name | Should -Be $testCategory2
            $newresults[1].CategoryType | Should -Be "MultiServerJob"
        }

        It "Should not write over existing job categories" {
            $results = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategory1 -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "already exists" | Should -Be $true
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $testCategoryOutput = "OutputValidationTest"
            $result = New-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategoryOutput -EnableException
        }

        AfterAll {
            Remove-DbaAgentJobCategory -SqlInstance $TestConfig.InstanceSingle -Category $testCategoryOutput -ErrorAction SilentlyContinue
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Agent.JobCategory]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'ID',
                'CategoryType',
                'JobCount'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}