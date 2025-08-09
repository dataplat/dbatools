#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbccProcCache",
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
        $props = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "Count",
            "Used",
            "Active",
            "CacheSize",
            "CacheUsed",
            "CacheActive"
        )
        $result = Get-DbaDbccProcCache -SqlInstance $TestConfig.instance2
    }

    Context "Validate standard output" {
        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }
    }

    Context "Command returns proper info" {
        It "Returns results for DBCC PROCCACHE" {
            $result | Should -Not -BeNullOrEmpty
        }
    }
}