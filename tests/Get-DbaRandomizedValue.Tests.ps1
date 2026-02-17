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
            $result = Get-DbaRandomizedValue -DataType varchar -OutVariable "global:dbatoolsciOutput"

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
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a String for varchar DataType" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [System.String]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Not -BeNullOrEmpty
        }
    }
}