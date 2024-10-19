param($ModuleName = 'dbatools')

Describe "Get-DbaRandomizedDataset" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRandomizedDataset
        }
        It "Should have Template as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Template
        }
        It "Should have TemplateFile as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter TemplateFile
        }
        It "Should have Rows as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Rows
        }
        It "Should have Locale as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Locale
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
