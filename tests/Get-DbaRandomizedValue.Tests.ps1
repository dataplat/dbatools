param($ModuleName = 'dbatools')

Describe "Get-DbaRandomizedValue" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRandomizedValue
        }
        $params = @(
            "DataType",
            "RandomizerType",
            "RandomizerSubType",
            "Min",
            "Max",
            "Precision",
            "CharacterString",
            "Format",
            "Symbol",
            "Separator",
            "Value",
            "Locale",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command returns values" {
        It "Should return a System.String type" {
            $result = Get-DbaRandomizedValue -DataType varchar
            $result | Should -BeOfType [String]
        }

        It "Should return random string of max length 255" {
            $result = Get-DbaRandomizedValue -DataType varchar
            $result.Length | Should -BeGreaterThan 1
            $result.Length | Should -BeLessOrEqual 255
        }

        It "Should return a random address zipcode" {
            $result = Get-DbaRandomizedValue -RandomizerSubType Zipcode -Format "#####"
            $result.Length | Should -Be 5
            $result | Should -Match '^\d{5}$'
        }
    }
}
