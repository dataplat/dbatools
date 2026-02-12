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
        BeforeAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $results = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle | Where-Object MonitorStatus
        }

        AfterAll {
            $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.InstanceSingle
        }

        It "Adds the mirror monitor" {
            $results.MonitorStatus | Should -Be "Added"
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results.psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $results.ComputerName | Should -Not -BeNullOrEmpty
            $results.InstanceName | Should -Not -BeNullOrEmpty
            $results.SqlInstance | Should -Not -BeNullOrEmpty
            $results.MonitorStatus | Should -Be "Added"
        }
    }
}