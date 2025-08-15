#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentAlertCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Category",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command gets alert categories" {
        BeforeAll {
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $null = New-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category dbatoolsci_testcategory, dbatoolsci_testcategory2

            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }

        AfterAll {
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $null = Remove-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category dbatoolsci_testcategory, dbatoolsci_testcategory2 -Confirm:$false
        }

        It "Should get at least 2 categories" {
            $results = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 | Where-Object Name -match "dbatoolsci"
            $results.Count | Should -BeGreaterThan 1
        }

        It "Should get the dbatoolsci_testcategory category" {
            $results = Get-DbaAgentAlertCategory -SqlInstance $TestConfig.instance2 -Category dbatoolsci_testcategory | Where-Object Name -match "dbatoolsci"
            $results.Count | Should -BeExactly 1
        }
    }
}