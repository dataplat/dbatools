#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgentLog",
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
                "LogNumber",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command gets agent log" {
        It "Returns results" {
            $results = Get-DbaAgentLog -SqlInstance $TestConfig.InstanceSingle

            $results | Should -Not -BeNullOrEmpty
            ($results | Select-Object -First 1).LogDate | Should -BeOfType DateTime
        }
    }

    Context "Command gets current agent log using LogNumber parameter" {
        BeforeAll {
            $results = Get-DbaAgentLog -SqlInstance $TestConfig.InstanceSingle -LogNumber 0
        }

        It "Results are not empty" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}