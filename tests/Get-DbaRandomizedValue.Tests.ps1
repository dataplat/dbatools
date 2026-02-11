#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRandomizedValue",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "DataType",
                "RandomizerType",
                "RandomizerSubType",
                "Min",
                "Max",
                "Precision",
                "CharacterString",
                "Format",
                "Separator",
                "Symbol",
                "Locale",
                "Value",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command returns values" {
        It "Should return a String type" {
            $result = Get-DbaRandomizedValue -DataType varchar

            $result.GetType().Name | Should -Be "String"
        }

        It "Should return random string of max length 255" {
            $result = Get-DbaRandomizedValue -DataType varchar

            $result.Length | Should -BeGreaterThan 1
        }

        It "Should return a random address zipcode" -Skip:$env:AppVeyor {
            # Skip It on AppVeyor because: Method invocation failed because [Bogus.DataSets.Name] does not contain a method named 'ZipCode'.

            $result = Get-DbaRandomizedValue -RandomizerType Address -RandomizerSubType Zipcode -Format "#####"

            $result.Length | Should -Be 5
        }
    }

    Context "Output validation" {
        It "Returns a string when using varchar DataType" {
            $result = Get-DbaRandomizedValue -DataType varchar
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [System.String]
        }

        It "Returns an integer when using int DataType" {
            $result = Get-DbaRandomizedValue -DataType int
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [System.Int32]
        }

        It "Returns a string in date format when using date DataType" {
            $result = Get-DbaRandomizedValue -DataType date
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "^\d{4}-\d{2}-\d{2}$"
        }

        It "Returns 0 or 1 when using bit DataType" {
            $result = Get-DbaRandomizedValue -DataType bit
            $result | Should -BeIn 0, 1
        }
    }
}