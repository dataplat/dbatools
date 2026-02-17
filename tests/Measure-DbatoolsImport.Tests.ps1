#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Measure-DbatoolsImport",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It -Skip "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $global:dbatoolsciOutput = @(Measure-DbatoolsImport)
    }

    Context "When measuring import performance" {
        It "Should return results" {
            $global:dbatoolsciOutput | Should -Not -BeNullOrEmpty
        }

        It "Should have Action property populated" {
            $global:dbatoolsciOutput[0].Action | Should -Not -BeNullOrEmpty
        }

        It "Should have Duration property populated" {
            $global:dbatoolsciOutput[0].Duration | Should -Not -BeNullOrEmpty
        }

        It "Should only return steps with non-zero duration" {
            $global:dbatoolsciOutput | ForEach-Object { $PSItem.Duration | Should -Not -Be "00:00:00" }
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "Action",
                "Duration"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
