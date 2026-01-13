#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDefaultPath",
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
    Context "returns proper information" {
        BeforeAll {
            $results = Get-DbaDefaultPath -SqlInstance $TestConfig.InstanceSingle
        }

        It "Data returns a value that contains :\" {
            $results.Data -match ":\\" | Should -BeTrue
        }

        It "Log returns a value that contains :\" {
            $results.Log -match ":\\" | Should -BeTrue
        }

        It "Backup returns a value that contains :\" {
            $results.Backup -match ":\\" | Should -BeTrue
        }

        It "ErrorLog returns a value that contains :\" {
            $results.ErrorLog -match ":\\" | Should -BeTrue
        }
    }
}