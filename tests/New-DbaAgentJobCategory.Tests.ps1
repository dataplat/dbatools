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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testCategory1 = "CategoryTest1"
        $testCategory2 = "CategoryTest2"
        $categoriesToCleanup = @()
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category $testCategory1, $testCategory2 -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "New Agent Job Category is added properly" {
        BeforeAll {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category $testCategory1
            $results.Name | Should -Be $testCategory1
            $results.CategoryType | Should -Be "LocalJob"
            $global:categoriesToCleanup += $testCategory1
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category $testCategory2 -CategoryType MultiServerJob
            $results.Name | Should -Be $testCategory2
            $results.CategoryType | Should -Be "MultiServerJob"
            $global:categoriesToCleanup += $testCategory2
        }

        It "Should actually for sure exist" {
            $newresults = Get-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category $testCategory1, $testCategory2
            $newresults[0].Name | Should -Be $testCategory1
            $newresults[0].CategoryType | Should -Be "LocalJob"
            $newresults[1].Name | Should -Be $testCategory2
            $newresults[1].CategoryType | Should -Be "MultiServerJob"
        }

        It "Should not write over existing job categories" {
            $results = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category $testCategory1 -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "already exists" | Should -Be $true
        }
    }
}