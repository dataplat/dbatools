#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Value",
                "Name",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Set configuration" {
        BeforeAll {
            $remotequerytimeout = (Get-DbaSpConfigure -SqlInstance $TestConfig.instance1 -ConfigName RemoteQueryTimeout).ConfiguredValue
            $newtimeout = $remotequerytimeout + 1

            # Sanity check
            if ($null -eq $remotequerytimeout) {
                return
            }
        }

        It "changes the remote query timeout from original value to new value" {
            $results = Set-DbaSpConfigure -SqlInstance $TestConfig.instance1 -ConfigName RemoteQueryTimeout -Value $newtimeout
            $results.PreviousValue | Should -Be $remotequerytimeout
            $results.NewValue | Should -Be $newtimeout
        }

        It "changes the remote query timeout back to original value" {
            $results = Set-DbaSpConfigure -SqlInstance $TestConfig.instance1 -ConfigName RemoteQueryTimeout -Value $remotequerytimeout
            $results.PreviousValue | Should -Be $newtimeout
            $results.NewValue | Should -Be $remotequerytimeout
        }

        It "returns a warning when the new value is the same as the old" {
            $results = Set-DbaSpConfigure -SqlInstance $TestConfig.instance1 -ConfigName RemoteQueryTimeout -Value $remotequerytimeout -WarningVariable warning -WarningAction SilentlyContinue
            $warning -match "existing" | Should -Be $true
        }
    }
}
