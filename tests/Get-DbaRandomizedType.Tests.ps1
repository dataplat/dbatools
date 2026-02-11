#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRandomizedType",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "RandomizedType",
                "RandomizedSubType",
                "Pattern",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns types" {
        BeforeAll {
            $allTypes = Get-DbaRandomizedType
            $zipcodeResult = Get-DbaRandomizedType -RandomizedSubType Zipcode
            $namePatternTypes = Get-DbaRandomizedType -Pattern Name
        }

        It "Should have at least 205 rows" {
            $allTypes.Count | Should -BeGreaterOrEqual 205
        }

        It "Should return correct type based on subtype" {
            $zipcodeResult.Type | Should -Be "Address"
        }

        It "Should return values based on pattern" {
            $namePatternTypes.Count | Should -BeGreaterOrEqual 26
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaRandomizedType
        }

        It "Returns output of type PSCustomObject" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $result[0].PSObject.Properties.Name | Should -Contain "Type"
            $result[0].PSObject.Properties.Name | Should -Contain "SubType"
        }

        It "Has non-null Type and SubType values" {
            $result[0].Type | Should -Not -BeNullOrEmpty
            $result[0].SubType | Should -Not -BeNullOrEmpty
        }
    }
}