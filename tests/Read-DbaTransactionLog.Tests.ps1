#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaTransactionLog",
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
                "Database",
                "IgnoreLimit",
                "RowLimit",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $result = Read-DbaTransactionLog -SqlInstance $TestConfig.InstanceSingle -Database master -RowLimit 10
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType System.Data.DataRow
        }

        It "Has the expected transaction log properties" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties.Name | Should -Contain "Current LSN"
            $result[0].psobject.Properties.Name | Should -Contain "Operation"
            $result[0].psobject.Properties.Name | Should -Contain "Transaction ID"
        }

        It "Respects the RowLimit parameter" {
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeLessOrEqual 10
        }
    }
}