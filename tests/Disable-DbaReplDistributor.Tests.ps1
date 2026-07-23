#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaReplDistributor",
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
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# TODO: Is this needed? Add-ReplicationLibrary

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: fully removing distribution requires a configured distributor with a
    # distribution database, which the GitHub Actions replication harness provides
    # (gh-actions-repl-*) - that live UninstallDistributor leg is DEFERRED-TO-GATE. What IS
    # characterizable on a plain instance with no distribution configured is the branch the source
    # takes when the instance is NOT a distributor: it connects, reads the ReplicationServer's
    # IsDistributor flag, finds it false, and raises "isn't currently enabled for distributing." via
    # Stop-Function. That single leg exercises the module hop, the live connection, the
    # Get-DbaReplServer lookup, the IsDistributor branch, and the warning surface end to end.
    Context "Guarding an instance that is not a distributor" {
        It "Warns that the instance isn't currently enabled for distributing" {
            $splatDisable = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "distWarn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $result = Disable-DbaReplDistributor @splatDisable
            $result | Should -BeNullOrEmpty
            ($distWarn -join "`n") | Should -Match "isn't currently enabled for distributing"
        }
    }
}
