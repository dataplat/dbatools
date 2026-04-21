#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "appveyor.common",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        . "$PSScriptRoot\appveyor.common.ps1"
    }

    Context "Get-FunctionNameFromTestFile" {
        It "returns the command name for standard tests" {
            $testPath = Join-Path $PSScriptRoot "Get-DbaBuild.Tests.ps1"

            Get-FunctionNameFromTestFile $testPath | Should -Be "Get-DbaBuild"
        }

        It "returns the base command name for suffixed tests" {
            $testPath = Join-Path $PSScriptRoot "Get-DbaBuild.one.Tests.ps1"

            Get-FunctionNameFromTestFile $testPath | Should -Be "Get-DbaBuild"
        }
    }
}