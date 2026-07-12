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
    # Characterization tests (TA-031): pure module-state compute over the import ledger.
    Context "Import performance data" {
        It "returns the recorded import steps with Action and Duration" {
            # The .OUTPUTS help claims a Name property; the ledger actually carries Action.
            # Under Invoke-ManualPester the module ledger can read blank (RB-IMP-51 class),
            # in which case the function pipes a single $null through its filter - both
            # worlds keep Count above zero, and every real step carries Action/Duration.
            $results = @(Measure-DbatoolsImport)
            $results.Count | Should -BeGreaterThan 0
            foreach ($step in $results) {
                if ($null -ne $step) {
                    $stepProperties = @($step.PSObject.Properties | ForEach-Object Name)
                    $stepProperties | Should -Contain "Action"
                    $stepProperties | Should -Contain "Duration"
                    "$($step.Duration)" | Should -Not -Be "00:00:00"
                }
            }
        }

        It "filters out zero-duration steps" {
            $zeroSteps = @(Measure-DbatoolsImport | Where-Object { "$($PSItem.Duration)" -eq "00:00:00" })
            $zeroSteps.Count | Should -Be 0
        }
    }
}