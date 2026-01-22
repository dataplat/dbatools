#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaLocaleSetting",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets LocaleSettings" {
        It "Gets results" {
            $results = Get-DbaLocaleSetting -ComputerName $env:ComputerName
            $results | Should -Not -Be $null
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaLocaleSetting -ComputerName $env:ComputerName -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has ComputerName property" {
            $result.PSObject.Properties.Name | Should -Contain "ComputerName" -Because "ComputerName is always included"
        }

        It "Has dynamic registry properties" {
            # The command dynamically reads registry values, so we test for common locale properties
            $commonProps = @('Locale', 'LocaleName', 'sLanguage', 'sDecimal', 'sList')
            $actualProps = $result.PSObject.Properties.Name
            $foundProps = $commonProps | Where-Object { $_ -in $actualProps }
            $foundProps.Count | Should -BeGreaterThan 0 -Because "at least some common locale properties should be present"
        }
    }
}