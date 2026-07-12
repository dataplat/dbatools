#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-Dbatools",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Development",
                "Cleanup",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-050). The command is a deprecation stub: its entire body is
    # one unconditional Write-Warning (blockless body = END-block semantics; no ShouldProcess
    # call, so -WhatIf does not suppress it).

    Context "Deprecation warning" {
        It "Warns to use Install-Module/Update-Module and emits nothing" {
            $results = @(Update-Dbatools -WarningVariable warn -WarningAction SilentlyContinue)
            $results.Count | Should -BeExactly 0
            @($warn).Count | Should -BeExactly 1
            "$($warn[0])" | Should -Match "deprecated.*Install-Module"
        }

        It "Warns identically under -WhatIf and with the switches bound" {
            $null = Update-Dbatools -Development -Cleanup -WhatIf -WarningVariable warn -WarningAction SilentlyContinue
            @($warn).Count | Should -BeExactly 1
        }
    }
}