#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDefaultPath",
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
                "Type",
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "returns proper information" {
        BeforeAll {
            $results = Set-DbaDefaultPath -SqlInstance $TestConfig.instance1 -Type Backup -Path "C:\temp"
        }

        It "Data returns a value that contains :\" {
            $results.Data -match ":\\"
        }
        It "Log returns a value that contains :\" {
            $results.Log -match ":\\"
        }
        It "Backup returns a value that contains :\" {
            $results.Backup -match ":\\"
        }
        It "ErrorLog returns a value that contains :\" {
            $results.ErrorLog -match ":\\"
        }
    }
}