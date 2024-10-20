param($ModuleName = 'dbatools')

Describe "Convert-DbaMaskingValue" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Convert-DbaMaskingValue
        }
        $parms = @(
            'Value',
            'DataType',
            'Nullable',
            'EnableException'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
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
        It "Should return a text value for <DataType>" -ForEach @(
            @{ DataType = 'char'; Value = "this is just text"; Expected = "'this is just text'" }
            @{ DataType = 'nchar'; Value = "this is just text"; Expected = "'this is just text'" }
            @{ DataType = 'nvarchar'; Value = "this is just text"; Expected = "'this is just text'" }
            @{ DataType = 'varchar'; Value = "this is just text"; Expected = "'this is just text'" }
            @{ DataType = 'varchar'; Value = "2.13"; Expected = "'2.13'" }
            @{ DataType = 'nchar'; Value = "'this is just text'"; Expected = "'''this is just text'''" }
        ) {
            $convertedValue = Convert-DbaMaskingValue -Value $Value -DataType $DataType
            $convertedValue.NewValue | Should -Be $Expected
        }
    }

    Context "Date and time data types" {
        It "Should return a text value for <DataType>" -ForEach @(
            @{ DataType = 'date'; Value = "2020-10-05 10:10:10.1234567"; Expected = "'2020-10-05'" }
            @{ DataType = 'time'; Value = "2020-10-05 10:10:10.1234567"; Expected = "'10:10:10.1234567'" }
            @{ DataType = 'datetime'; Value = "2020-10-05 10:10:10.1234567"; Expected = "'2020-10-05 10:10:10.123'" }
        ) {
            $convertedValue = Convert-DbaMaskingValue -Value $Value -DataType $DataType
            $convertedValue.NewValue | Should -Be $Expected
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
