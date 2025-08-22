#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstanceInstallDate",
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
                "Credential",
                "IncludeWindows",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets SQL Server Install Date" {
        It "Gets results" {
            $results = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets SQL Server Install Date and Windows Install Date" {
        It "Gets results" {
            $results = Get-DbaInstanceInstallDate -SqlInstance $TestConfig.instance2 -IncludeWindows
            $results | Should -Not -BeNullOrEmpty
        }
    }
}