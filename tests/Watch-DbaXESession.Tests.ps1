#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Watch-DbaXESession",
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
                "Session",
                "InputObject",
                "Raw",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command functions as expected" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Stop-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Start-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        # This command is special and runs infinitely so don't actually try to run it
        It "warns if XE session is not running" {
            $results = Watch-DbaXESession -SqlInstance $TestConfig.InstanceSingle -Session system_health -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Match "system_health is not running"
        }
    }
}