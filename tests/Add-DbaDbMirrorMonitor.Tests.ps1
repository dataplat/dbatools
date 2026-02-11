#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaDbMirrorMonitor",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When adding mirror monitor" {
        AfterAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle
        }

        It "Adds the mirror monitor" {
            $results = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle
            $results.MonitorStatus | Should -Be "Added"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $result = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle | Where-Object MonitorStatus
        }

        AfterAll {
            Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result.psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.MonitorStatus | Should -Be "Added"
        }
    }
}