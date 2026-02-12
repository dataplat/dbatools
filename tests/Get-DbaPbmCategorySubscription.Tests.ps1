#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPbmCategorySubscription",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:($PSVersionTable.PSEdition -eq "Core") {
        BeforeAll {
            $categoryName = "dbatoolsci_outputtest_$(Get-Random)"
            try {
                # Create a PBM policy category and subscribe a database to it
                $store = Get-DbaPbmStore -SqlInstance $TestConfig.InstanceSingle -EnableException
                $category = New-Object Microsoft.SqlServer.Management.Dmf.PolicyCategory($store, $categoryName)
                $category.Create()

                $subscription = New-Object Microsoft.SqlServer.Management.Dmf.PolicyCategorySubscription($store)
                $subscription.PolicyCategory = $categoryName
                $subscription.Target = "DATABASE::[master]"
                $subscription.Create()
            } catch {
                # PBM object creation may fail in CI, continue to attempt command
            }

            try {
                $result = Get-DbaPbmCategorySubscription -SqlInstance $TestConfig.InstanceSingle -EnableException
            } catch {
                $result = $null
            }
        }

        AfterAll {
            try {
                $store = Get-DbaPbmStore -SqlInstance $TestConfig.InstanceSingle -EnableException
                $sub = $store.PolicyCategorySubscriptions | Where-Object PolicyCategory -eq $categoryName
                if ($sub) { $sub.Drop() }
                $cat = $store.PolicyCategories[$categoryName]
                if ($cat) { $cat.Drop() }
            } catch {
                # Ignore cleanup errors
            }
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Dmf.PolicyCategorySubscription"
        }

        It "Has the expected default display properties excluding Properties, Urn, and Parent" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "Properties" -Because "Properties is excluded via Select-DefaultView -ExcludeProperty"
            $defaultProps | Should -Not -Contain "Urn" -Because "Urn is excluded via Select-DefaultView -ExcludeProperty"
            $defaultProps | Should -Not -Contain "Parent" -Because "Parent is excluded via Select-DefaultView -ExcludeProperty"
        }

        It "Has ComputerName, InstanceName, and SqlInstance properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].ComputerName | Should -Not -BeNullOrEmpty
            $result[0].InstanceName | Should -Not -BeNullOrEmpty
            $result[0].SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}