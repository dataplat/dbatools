#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsConfigValue",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FullName",
                "Fallback",
                "NotNull"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Set a test configuration value
            Set-DbatoolsConfig -FullName 'Test.OutputValidation' -Value 'TestValue'
            $result = Get-DbatoolsConfigValue -FullName 'Test.OutputValidation'
        }

        It "Returns a value (non-null)" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Returns the correct type based on stored value" {
            $result | Should -BeOfType [string]
        }

        It "Returns the actual stored value" {
            $result | Should -Be 'TestValue'
        }
    }

    Context "Output with -Fallback parameter" {
        BeforeAll {
            $result = Get-DbatoolsConfigValue -FullName 'NonExistent.Config' -Fallback 'DefaultValue'
        }

        It "Returns the fallback value when configuration doesn't exist" {
            $result | Should -Be 'DefaultValue'
        }
    }

    Context "Output with different value types" {
        It "Returns string values correctly" {
            Set-DbatoolsConfig -FullName 'Test.String' -Value 'StringValue'
            $result = Get-DbatoolsConfigValue -FullName 'Test.String'
            $result | Should -BeOfType [string]
            $result | Should -Be 'StringValue'
        }

        It "Returns integer values correctly" {
            Set-DbatoolsConfig -FullName 'Test.Integer' -Value 42
            $result = Get-DbatoolsConfigValue -FullName 'Test.Integer'
            $result | Should -BeOfType [int]
            $result | Should -Be 42
        }

        It "Returns boolean values correctly" {
            Set-DbatoolsConfig -FullName 'Test.Boolean' -Value $true
            $result = Get-DbatoolsConfigValue -FullName 'Test.Boolean'
            $result | Should -BeOfType [bool]
            $result | Should -Be $true
        }

        It "Converts 'Mandatory' string to boolean true" {
            Set-DbatoolsConfig -FullName 'Test.Mandatory' -Value 'Mandatory'
            $result = Get-DbatoolsConfigValue -FullName 'Test.Mandatory'
            $result | Should -BeOfType [bool]
            $result | Should -Be $true
        }

        It "Converts 'Optional' string to boolean false" {
            Set-DbatoolsConfig -FullName 'Test.Optional' -Value 'Optional'
            $result = Get-DbatoolsConfigValue -FullName 'Test.Optional'
            $result | Should -BeOfType [bool]
            $result | Should -Be $false
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>