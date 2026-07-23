#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaReplDistributor",
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
                "DistributionDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: actually installing a distributor requires the native RMO replication
    # libraries and a real distribution database, which the GitHub Actions replication harness
    # provides (gh-actions-repl-*) - that live InstallDistributor leg is DEFERRED-TO-GATE. The
    # source has no pre-connection guard: its only action is gated by ShouldProcess. What IS
    # characterizable on a plain instance is that -WhatIf routes through the module hop to the real
    # cmdlet, so the install block is skipped, nothing is emitted, and the instance is NOT turned
    # into a distributor. That leg exercises the hop, the live connection, the Get-DbaReplServer
    # lookup, and the ShouldProcess wiring while asserting the side effect did not happen. Target is
    # a standalone instance not configured for distribution.
    Context "Honoring -WhatIf" {
        It "Skips the install and emits nothing under -WhatIf, leaving the instance a non-distributor" {
            $splatEnable = @{
                SqlInstance = $TestConfig.InstanceMulti1
                WhatIf      = $true
            }
            $result = Enable-DbaReplDistributor @splatEnable
            $result | Should -BeNullOrEmpty
            (Get-DbaReplServer -SqlInstance $TestConfig.InstanceMulti1 -WarningAction SilentlyContinue).IsDistributor | Should -Not -BeTrue
        }
    }
}