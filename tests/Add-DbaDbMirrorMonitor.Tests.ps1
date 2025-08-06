#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName               = "dbatools",
    $CommandName              = [System.IO.Path]::GetFileName($PSCommandPath.Replace('.Tests.ps1', '')),
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaDbMirrorMonitor
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag "IntegrationTests" {
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
