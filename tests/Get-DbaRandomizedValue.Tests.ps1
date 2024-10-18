param($ModuleName = 'dbatools')

Describe "Get-DbaRandomizedValue" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRandomizedValue
        }
        It "Should have DataType as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter DataType -Type System.String -Mandatory:$false
        }
        It "Should have RandomizerType as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter RandomizerType -Type System.String -Mandatory:$false
        }
        It "Should have RandomizerSubType as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter RandomizerSubType -Type System.String -Mandatory:$false
        }
        It "Should have Min as a non-mandatory System.Object parameter" {
            $CommandUnderTest | Should -HaveParameter Min -Type System.Object -Mandatory:$false
        }
        It "Should have Max as a non-mandatory System.Object parameter" {
            $CommandUnderTest | Should -HaveParameter Max -Type System.Object -Mandatory:$false
        }
        It "Should have Precision as a non-mandatory System.Int32 parameter" {
            $CommandUnderTest | Should -HaveParameter Precision -Type System.Int32 -Mandatory:$false
        }
        It "Should have CharacterString as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter CharacterString -Type System.String -Mandatory:$false
        }
        It "Should have Format as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Format -Type System.String -Mandatory:$false
        }
        It "Should have Symbol as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Symbol -Type System.String -Mandatory:$false
        }
        It "Should have Separator as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Separator -Type System.String -Mandatory:$false
        }
        It "Should have Value as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Value -Type System.String -Mandatory:$false
        }
        It "Should have Locale as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Locale -Type System.String -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
