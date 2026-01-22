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

    Context "Output Validation - DataType Parameter" {
        It "Returns System.Int64 for bigint data type" {
            $result = Get-DbaRandomizedValue -DataType bigint -EnableException
            $result | Should -BeOfType [System.Int64]
        }

        It "Returns System.Int32 for int data type" {
            $result = Get-DbaRandomizedValue -DataType int -EnableException
            $result | Should -BeOfType [System.Int32]
        }

        It "Returns System.Int32 for bit data type" {
            $result = Get-DbaRandomizedValue -DataType bit -EnableException
            $result | Should -BeOfType [System.Int32]
            $result | Should -BeIn @(0, 1)
        }

        It "Returns System.Decimal for decimal data type" {
            $result = Get-DbaRandomizedValue -DataType decimal -Min 1 -Max 100 -EnableException
            $result | Should -BeOfType [System.Decimal]
        }

        It "Returns System.Decimal for money data type" {
            $result = Get-DbaRandomizedValue -DataType money -Min 1 -Max 100 -EnableException
            $result | Should -BeOfType [System.Decimal]
        }

        It "Returns System.String for varchar data type" {
            $result = Get-DbaRandomizedValue -DataType varchar -EnableException
            $result | Should -BeOfType [System.String]
        }

        It "Returns System.String for date data type" {
            $result = Get-DbaRandomizedValue -DataType date -EnableException
            $result | Should -BeOfType [System.String]
            $result | Should -Match '^\d{4}-\d{2}-\d{2}$'
        }

        It "Returns System.String for datetime data type" {
            $result = Get-DbaRandomizedValue -DataType datetime -EnableException
            $result | Should -BeOfType [System.String]
            $result | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$'
        }

        It "Returns System.String for guid data type" {
            $result = Get-DbaRandomizedValue -DataType guid -EnableException
            $result | Should -BeOfType [System.String]
            $result | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }
    }

    Context "Output Validation - RandomizerType Parameter" {
        It "Returns System.String for Address/City" {
            $result = Get-DbaRandomizedValue -RandomizerType Address -RandomizerSubType City -EnableException
            $result | Should -BeOfType [System.String]
        }

        It "Returns System.String for Name/FirstName" {
            $result = Get-DbaRandomizedValue -RandomizerType Name -RandomizerSubType FirstName -EnableException
            $result | Should -BeOfType [System.String]
        }

        It "Returns System.String for Internet/Email" {
            $result = Get-DbaRandomizedValue -RandomizerType Internet -RandomizerSubType Email -EnableException
            $result | Should -BeOfType [System.String]
        }

        It "Returns System.Int32 for Random/Int" {
            $result = Get-DbaRandomizedValue -RandomizerType Random -RandomizerSubType Int -Min 1 -Max 100 -EnableException
            $result | Should -BeOfType [System.Int32]
        }

        It "Returns System.Double for Address/Latitude" {
            $result = Get-DbaRandomizedValue -RandomizerType Address -RandomizerSubType Latitude -EnableException
            $result | Should -BeOfType [System.Double]
        }
    }

    Context "Output Validation - RandomizerSubType Only" {
        It "Returns System.String when using RandomizerSubType without RandomizerType" {
            $result = Get-DbaRandomizedValue -RandomizerSubType FirstName -EnableException
            $result | Should -BeOfType [System.String]
        }
    }
}