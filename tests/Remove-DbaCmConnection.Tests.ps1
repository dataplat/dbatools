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
Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        It "Returns no output when removing a cached connection" {
            # Set up a connection in the cache by using Get-DbaCmConnection on a known computer
            $null = Get-DbaCmConnection
            $result = Remove-DbaCmConnection -ComputerName $env:COMPUTERNAME -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }
}