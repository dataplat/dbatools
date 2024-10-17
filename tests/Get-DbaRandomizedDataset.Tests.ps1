param($ModuleName = 'dbatools')

Describe "Get-DbaRandomizedDataset" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRandomizedDataset
        }
        It "Should have Template as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Template -Type String[] -Not -Mandatory
        }
        It "Should have TemplateFile as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter TemplateFile -Type String[] -Not -Mandatory
        }
        It "Should have Rows as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter Rows -Type Int32 -Not -Mandatory
        }
        It "Should have Locale as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Locale -Type String -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command generates data sets" {
        BeforeAll {
            $rowCount = 10
            $dataset = Get-DbaRandomizedDataset -Template PersonalData -Rows $rowCount
        }

        It "Should have $rowCount rows" {
            $dataset.Count | Should -Be 10
        }
    }
}
