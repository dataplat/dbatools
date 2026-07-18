#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Repair-DbaInstanceName",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "AutoFix",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    # Characterization context (W1-094 law: an empty run is never green). The command renames
    # a wrongly-named instance, so the lab-safe characterization is the analysis pass on a
    # correctly-named instance: source line 126 Stop-Function -Continue with the "Good news!"
    # message (a warning in non-EE mode, no mutation ever attempted).
    Context "When analyzing a correctly named instance" {
        It "Warns that the name does not need to be changed" {
            $null = Repair-DbaInstanceName -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue -WarningVariable repairWarning
            $repairWarning | Should -Match "does not need to be changed"
        }
    }
}