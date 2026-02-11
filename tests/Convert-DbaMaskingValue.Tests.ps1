#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Convert-DbaMaskingValue",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Value",
                "DataType",
                "Nullable",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Null values" {
        It "Should return a single 'NULL' value" {
            $value = $null
            $convertedValue = Convert-DbaMaskingValue -Value $value -Nullable:$true
            $convertedValue.NewValue | Should -Be "NULL"
        }

        It "Should return multiple 'NULL' values" {
            $value = @($null, $null)
            $convertedValues = Convert-DbaMaskingValue -Value $value -Nullable:$true
            $convertedValues[0].NewValue | Should -Be "NULL"
            $convertedValues[1].NewValue | Should -Be "NULL"
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
            $convertedValues = Convert-DbaMaskingValue -Value $value -Nullable:$true
            $convertedValues[0].NewValue | Should -Be "NULL"
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

    Context "Output validation" {
        BeforeAll {
            $result = Convert-DbaMaskingValue -Value "test" -DataType varchar
        }

        It "Returns output of type PSCustomObject" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected properties" {
            $expectedProps = @("OriginalValue", "NewValue", "DataType", "ErrorMessage")
            foreach ($prop in $expectedProps) {
                $result.psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Returns correct property values for a varchar conversion" {
            $result.OriginalValue | Should -Be "test"
            $result.NewValue | Should -Be "'test'"
            $result.DataType | Should -Be "varchar"
        }
    }
}