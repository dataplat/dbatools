param($ModuleName = 'dbatools')

Describe "Get-DbaRandomizedValue" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRandomizedValue
        }
        It "Should have DataType as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DataType
        }
        It "Should have RandomizerType as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter RandomizerType
        }
        It "Should have RandomizerSubType as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter RandomizerSubType
        }
        It "Should have Min as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Min
        }
        It "Should have Max as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Max
        }
        It "Should have Precision as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Precision
        }
        It "Should have CharacterString as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter CharacterString
        }
        It "Should have Format as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Format
        }
        It "Should have Symbol as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Symbol
        }
        It "Should have Separator as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Separator
        }
        It "Should have Value as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Value
        }
        It "Should have Locale as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Locale
        }
        It "Should have EnableException as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
