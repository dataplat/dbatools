#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaServiceMasterKey",
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
                "SecurePassword",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Documentation Validation" {
        It "Should have .OUTPUTS documentation with output type" {
            $help = Get-Help $CommandName
            $help.returnValues | Should -Not -BeNullOrEmpty -Because "command should document its return type in .OUTPUTS"
            $help.returnValues.returnValue.type.name | Should -Match 'MasterKey' -Because "return type should be documented"
        }

        It "Should have .SYNOPSIS documentation" {
            $help = Get-Help $CommandName
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Should have .DESCRIPTION documentation" {
            $help = Get-Help $CommandName
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Should have at least one .EXAMPLE" {
            $help = Get-Help $CommandName
            $help.Examples.example.Count | Should -BeGreaterThan 0
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>