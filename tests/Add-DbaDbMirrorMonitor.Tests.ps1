#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Add-DbaDbMirrorMonitor" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaDbMirrorMonitor
            $expectedParameters = $TestConfig.CommonParameters

            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $actualParameters = $command.Parameters.Keys | Where-Object { $PSItem -notin "WhatIf", "Confirm" }
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $actualParameters | Should -BeNullOrEmpty
        }
    }
}

Describe "Add-DbaDbMirrorMonitor" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.instance2 -WarningAction SilentlyContinue
    }
    AfterAll {
        $null = Remove-DbaDbMirrorMonitor -SqlInstance $TestConfig.instance2 -WarningAction SilentlyContinue
    }

    Context "When adding mirror monitor" {
        BeforeAll {
            $results = Add-DbaDbMirrorMonitor -SqlInstance $TestConfig.instance2 -WarningAction SilentlyContinue
        }

        It "Adds the mirror monitor" {
            $results.MonitorStatus | Should -Be 'Added'
        }
    }
}
