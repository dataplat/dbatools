#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Add-DbaDbMirrorMonitor" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaDbMirrorMonitor
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
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
