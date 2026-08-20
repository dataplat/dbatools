#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcResourceGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "Name",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # These tests need a Windows failover cluster. No CI environment has one, so
    # $TestConfig.ClusterStorage is empty there and these tests skip. A lab that has a cluster sets
    # it, and then a regression has to fail these tests.
    Context "Retrieving the resource groups" -Skip:(-not $TestConfig.ClusterStorage) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $wsfcResourceGroups = @(Get-DbaWsfcResourceGroup -ComputerName $TestConfig.ClusterStorage)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns at least one resource group" {
            # Get-ResourceGroupState was defined inside this command and now lives in
            # private/functions, so this also proves the private function is still loaded.
            $wsfcResourceGroups | Should -Not -BeNullOrEmpty
        }

        It "Translates the state of every resource group" {
            $untranslatedGroups = ($wsfcResourceGroups | Where-Object { $PSItem.State -notin "Unknown", "Online", "Offline", "Failed" }).Name
            $untranslatedGroups | Should -BeNullOrEmpty
        }

        It "Filters by name" {
            $singleGroup = Get-DbaWsfcResourceGroup -ComputerName $TestConfig.ClusterStorage -Name $wsfcResourceGroups[0].Name
            $singleGroup.Name | Should -Be $wsfcResourceGroups[0].Name
        }
    }
}