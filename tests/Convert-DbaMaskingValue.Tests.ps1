$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\internal\functions', 'Convert-DbaMaskingValue.ps1'))

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'Value', 'DataType', 'Nullable', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

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
        It "Should return a text value" {
            $value = "this is just text"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType char
            $convertedValue.NewValue | Should -Be "'this is just text'"
        }

        It "Should return a text value" {
            $value = "this is just text"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType nchar
            $convertedValue.NewValue | Should -Be "'this is just text'"
        }

        It "Should return a text value" {
            $value = "this is just text"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType nvarchar
            $convertedValue.NewValue | Should -Be "'this is just text'"
        }

        It "Should return a text value" {
            $value = "this is just text"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType varchar
            $convertedValue.NewValue | Should -Be "'this is just text'"
        }

        It "Should return a text value" {
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
        It "Should return a text value" {
            $value = "2020-10-05 10:10:10.1234567"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType date
            $convertedValue.NewValue | Should -Be "'2020-10-05'"
        }

        It "Should return a text value" {
            $value = "2020-10-05 10:10:10.1234567"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType time
            $convertedValue.NewValue | Should -Be "'10:10:10.1234567'"
        }

        It "Should return a text value" {
            $value = "2020-10-05 10:10:10.1234567"
            $convertedValue = Convert-DbaMaskingValue -Value $value -DataType datetime
            $convertedValue.NewValue | Should -Be "'2020-10-05 10:10:10.123'"
        } #>
    }

    Context "Handling multiple values" {
        It "It should return a NULL value and text value" {
            $value = @($null, "this is just text")
            [array]$convertedValues = Convert-DbaMaskingValue -Value $value -Nullable:$true
            $convertedValues[0].NewValue | Should -Be 'NULL'
            $convertedValues[1].NewValue | Should -Be "'this is just text'"
        }
    }

    Context "Error handling" {
        It "It should return the value missing error" {
            { Convert-DbaMaskingValue -Value $null -DataType datetime -EnableException } | Should -Throw "Please enter a value"
        }
        It "It should return the data type missing error" {
            { Convert-DbaMaskingValue -Value "whatever" -EnableException } | Should -Throw "Please enter a data type"
        }
    }

}