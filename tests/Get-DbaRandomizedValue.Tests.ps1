param($ModuleName = 'dbatools')

Describe "Get-DbaRandomizedValue" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRandomizedValue
        }
        It "Should have DataType as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter DataType -Type String -Not -Mandatory
        }
        It "Should have RandomizerType as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter RandomizerType -Type String -Not -Mandatory
        }
        It "Should have RandomizerSubType as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter RandomizerSubType -Type String -Not -Mandatory
        }
        It "Should have Min as a non-mandatory Object parameter" {
            $CommandUnderTest | Should -HaveParameter Min -Type Object -Not -Mandatory
        }
        It "Should have Max as a non-mandatory Object parameter" {
            $CommandUnderTest | Should -HaveParameter Max -Type Object -Not -Mandatory
        }
        It "Should have Precision as a non-mandatory Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Precision -Type Int32 -Not -Mandatory
        }
        It "Should have CharacterString as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter CharacterString -Type String -Not -Mandatory
        }
        It "Should have Format as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Format -Type String -Not -Mandatory
        }
        It "Should have Symbol as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Symbol -Type String -Not -Mandatory
        }
        It "Should have Separator as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Separator -Type String -Not -Mandatory
        }
        It "Should have Value as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Value -Type String -Not -Mandatory
        }
        It "Should have Locale as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Locale -Type String -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command returns values" {
        It "Should return a String type" {
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
