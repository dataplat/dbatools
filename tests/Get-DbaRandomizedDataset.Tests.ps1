param($ModuleName = 'dbatools')

Describe "Get-DbaRandomizedDataset" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRandomizedDataset
        }
        It "Should have Template as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Template -Type System.String[] -Mandatory:$false
        }
        It "Should have TemplateFile as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter TemplateFile -Type System.String[] -Mandatory:$false
        }
        It "Should have Rows as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter Rows -Type System.Int32 -Mandatory:$false
        }
        It "Should have Locale as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Locale -Type System.String -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Object[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
