#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaDbMirrorMonitor",
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
    Context "When adding mirror monitor" {
        BeforeAll {
            $results = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.instance2
        }

        AfterAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.instance2
        }

        It "Adds the mirror monitor" {
            $results.MonitorStatus | Should -Be "Added"
        }
    }
}