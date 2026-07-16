#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaCmConnection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
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
    # Characterization context (W1-094 law: an empty run is never green). The CIM connection
    # cache is process-local state - no lab instance required.
    Context "When removing a registered connection" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = New-DbaCmConnection -ComputerName dbatoolsci-w3071
            $results = Remove-DbaCmConnection -ComputerName dbatoolsci-w3071 -Confirm:$false
            $remaining = @(Get-DbaCmConnection -ComputerName dbatoolsci-w3071)
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Removes the registered connection" {
            $remaining.Count | Should -Be 0
        }
    }
}
