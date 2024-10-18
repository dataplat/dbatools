param($ModuleName = 'dbatools')

Describe "Convert-DbaMaskingValue" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Convert-DbaMaskingValue
        }
        It "Should have Value as a parameter" {
            $CommandUnderTest | Should -HaveParameter Value -Type System.Object[]
        }
        It "Should have DataType as a parameter" {
            $CommandUnderTest | Should -HaveParameter DataType -Type System.String
        }
        It "Should have Nullable as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Nullable -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Null values" {
        It "Should return a single 'NULL' value" {
            $value = $null
            $convertedValue = Convert-DbaMaskingValue -Value $value -Nullable:$true
            $convertedValue.NewValue | Should -Be 'NULL'
        }

        It "Should return multiple 'NULL' values" {
            $value = @($null, $null)
            [array]$convertedValues = Convert-DbaMaskingValue -Value $value -Nullable:$true
            $convertedValues[0].NewValue | Should -Be 'NULL'
            $convertedValues[1].NewValue | Should -Be 'NULL'
        }
    }

    Context "Text data types" {
        It "Should return a text value for char data type" {
            $value = "this is just text"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType char
            $convertedValue.NewValue | Should -Be "'this is just text'"
        }

        It "Should return a text value for nchar data type" {
            $value = "this is just text"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType nchar
            $convertedValue.NewValue | Should -Be "'this is just text'"
        }

        It "Should return a text value for nvarchar data type" {
            $value = "this is just text"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType nvarchar
            $convertedValue.NewValue | Should -Be "'this is just text'"
        }

        It "Should return a text value for varchar data type" {
            $value = "this is just text"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType varchar
            $convertedValue.NewValue | Should -Be "'this is just text'"
        }

        It "Should return a text value for numeric string" {
            $value = "2.13"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType varchar
            $convertedValue.NewValue | Should -Be "'2.13'"
        }

        It "Should return a text value with multiple single quotes" {
            $value = "'this is just text'"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType nchar
            $convertedValue.NewValue | Should -Be "'''this is just text'''"
        }
    }

    Context "Date and time data types" {
        It "Should return a date value" {
            $value = "2020-10-05 10:10:10.1234567"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType date
            $convertedValue.NewValue | Should -Be "'2020-10-05'"
        }

        It "Should return a time value" {
            $value = "2020-10-05 10:10:10.1234567"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType time
            $convertedValue.NewValue | Should -Be "'10:10:10.1234567'"
        }

        It "Should return a datetime value" {
            $value = "2020-10-05 10:10:10.1234567"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType datetime
            $convertedValue.NewValue | Should -Be "'2020-10-05 10:10:10.123'"
        }
    }

    Context "Handling multiple values" {
        It "Should return a NULL value and text value" {
            $value = @($null, "this is just text")
            [array]$convertedValues = Convert-DbaMaskingValue -Value $value -Nullable:$true
            $convertedValues[0].NewValue | Should -Be 'NULL'
            $convertedValues[1].NewValue | Should -Be "'this is just text'"
        }
    }

    Context "Error handling" {
        It "Should throw an error when value is missing" {
            { Convert-DbaMaskingValue -Value $null -DataType datetime -EnableException } | Should -Throw "Please enter a value"
        }
        It "Should throw an error when data type is missing" {
            { Convert-DbaMaskingValue -Value "whatever" -EnableException } | Should -Throw "Please enter a data type"
        }
    }
}
