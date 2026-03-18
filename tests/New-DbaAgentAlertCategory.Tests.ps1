#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentAlertCategory",
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
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # TODO: This can be removed if we are sure that no other tests are not removing the EnableException parameter.

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "New Agent Alert Category is added properly" {
        AfterAll {
            $null = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category CategoryTest1, CategoryTest2 | Remove-DbaAgentAlertCategory
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category CategoryTest1
            $results.Name | Should -Be "CategoryTest1"
        }

        It "Should have the right name and category type" {
            $results = New-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category CategoryTest2
            $results.Name | Should -Be "CategoryTest2"
        }

        It "Should actually for sure exist" {
            $results = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category CategoryTest1, CategoryTest2
            $results[0].Name | Should -Be "CategoryTest1"
            $results[1].Name | Should -Be "CategoryTest2"
        }

        It "Should not write over existing job categories" {
            $results = New-DbaAgentAlertCategory -SqlInstance $TestConfig.InstanceSingle -Category CategoryTest1 -WarningAction SilentlyContinue
            $WarnVar | Should -Match "already exists"
        }
    }
}