#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Clear-DbaLatchStatistics",
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
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command executes properly and returns proper info" {
        BeforeAll {
            $splatClearLatch = @{
                SqlInstance = $TestConfig.instance1
                Confirm     = $false
            }
            $results = Clear-DbaLatchStatistics @splatClearLatch
        }

        It "Returns success" {
            $results.Status | Should -Be "Success"
        }
    }
}
