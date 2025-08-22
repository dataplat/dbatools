#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaInstanceName",
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
                "ExcludeSsrs",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command tests servername" {
        BeforeAll {
            $results = Test-DbaInstanceName -SqlInstance $TestConfig.instance2
        }

        It "should say rename is not required" {
            $results.RenameRequired | Should -Be $false
        }

        It "returns the correct properties" {
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "ServerName", "NewServerName", "RenameRequired", "Updatable", "Warnings", "Blockers"
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }
    }
}