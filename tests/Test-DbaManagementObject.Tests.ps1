#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "Test-DbaManagementObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

<#
    The below statement stays in for every test you build.
#>
$global:TestConfig = Get-TestConfig

<#
    Unit test is required for any command added
#>
Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "VersionNumber",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $versionMajor = (Connect-DbaInstance -SqlInstance $TestConfig.instance2).VersionMajor
    }

    Context "Command actually works" {
        BeforeAll {
            $trueResults = Test-DbaManagementObject -ComputerName $TestConfig.instance2 -VersionNumber $versionMajor
            $falseResults = Test-DbaManagementObject -ComputerName $TestConfig.instance2 -VersionNumber -1
        }

        It "Should have correct properties" {
            $expectedProps = @("ComputerName", "Version", "Exists")
            ($trueResults[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should return true for VersionNumber $versionMajor" {
            $trueResults.Exists | Should -Be $true
        }

        It "Should return false for VersionNumber -1" {
            $falseResults.Exists | Should -Be $false
        }
    }
}