#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaRandomizedDataset",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Template",
                "TemplateFile",
                "Rows",
                "Locale",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command generates data sets" {
        It "Should have $rowCount rows" {
            $rowCount = 10
            $dataset = Get-DbaRandomizedDataset -Template PersonalData -Rows $rowCount
            $dataset.Count | Should -Be 10
        }
    }

    Context "When no template is supplied" {
        It "Warns without eating an iteration of the caller's loop" {
            # The validation guards used to run Stop-Function -Continue without an enclosing loop -
            # the continue escaped the command and consumed an iteration of this very loop, so the
            # counter fell short (#10638).
            $loopCount = 0
            foreach ($i in 1..3) {
                $null = Get-DbaRandomizedDataset -WarningAction SilentlyContinue
                $loopCount++
            }
            $loopCount | Should -Be 3
            $WarnVar | Should -BeLike "*Please enter a template*"
        }
    }
}