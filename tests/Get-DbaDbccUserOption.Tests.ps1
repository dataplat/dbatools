#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbccUserOption",
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
                "Option",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $props = @("ComputerName", "InstanceName", "SqlInstance", "Option", "Value")
    }

    Context "Validate standard output" {
        BeforeAll {
            $result = Get-DbaDbccUserOption -SqlInstance $TestConfig.InstanceSingle
        }

        It "Should return property: ComputerName" {
            $result[0].PSObject.Properties["ComputerName"].Name | Should -Be "ComputerName"
        }

        It "Should return property: InstanceName" {
            $result[0].PSObject.Properties["InstanceName"].Name | Should -Be "InstanceName"
        }

        It "Should return property: SqlInstance" {
            $result[0].PSObject.Properties["SqlInstance"].Name | Should -Be "SqlInstance"
        }

        It "Should return property: Option" {
            $result[0].PSObject.Properties["Option"].Name | Should -Be "Option"
        }

        It "Should return property: Value" {
            $result[0].PSObject.Properties["Value"].Name | Should -Be "Value"
        }

        It "returns results for DBCC USEROPTIONS" {
            $result.Count | Should -BeGreaterThan 0
        }
    }

    Context "Accepts an Option Value" {
        BeforeAll {
            $result = Get-DbaDbccUserOption -SqlInstance $TestConfig.InstanceSingle -Option ansi_nulls
        }

        It "Gets results" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Returns only one result" {
            $result.Option | Should -Be "ansi_nulls"
        }
    }
}