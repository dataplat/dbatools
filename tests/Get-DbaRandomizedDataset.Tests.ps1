param($ModuleName = 'dbatools')

Describe "Get-DbaRandomizedDataset" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRandomizedDataset
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "Template",
                "TemplateFile",
                "Rows",
                "Locale",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
