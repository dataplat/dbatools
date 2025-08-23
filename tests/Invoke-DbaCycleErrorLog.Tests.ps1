#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaCycleErrorLog",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Validate output" {
        BeforeAll {
            $results = Invoke-DbaCycleErrorLog -SqlInstance $TestConfig.instance1 -Type instance
        }

        It "Should have correct properties" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "LogType",
                "IsSuccessful",
                "Notes"
            )
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should cycle instance error log" {
            $results.LogType | Should -Be "instance"
        }
    }
}