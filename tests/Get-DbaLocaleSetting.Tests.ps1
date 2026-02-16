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
            $results = Get-DbaLocaleSetting -ComputerName $env:ComputerName -OutVariable "global:dbatoolsciOutput"
            $results | Should -Not -Be $null
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the ComputerName property" {
            $global:dbatoolsciOutput[0].ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Should have locale-related properties from the registry" {
            $properties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            $properties | Should -Contain "ComputerName"
            $properties.Count | Should -BeGreaterThan 1
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}