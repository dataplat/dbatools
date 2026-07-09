#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaInstalledPatch",
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
    Context "Validate output" {
        It "has some output" {
            $result = Get-DbaInstalledPatch -ComputerName $TestConfig.InstanceSingle

            $WarnVar | Should -BeNullOrEmpty
            # On AppVeyor and freshly-built labs (RTM installs) there are no patches installed
            if (@($result).Count -eq 0) {
                Set-ItResult -Skipped -Because "no SQL Server patches are installed on this host"
            }
            $result | Should -Not -BeNullOrEmpty
        }
    }
}