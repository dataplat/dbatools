#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaReplPublishing",
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

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: fully removing the publisher role requires an instance configured for
    # publishing against a distributor, which the GitHub Actions replication harness provides
    # (gh-actions-repl-*) - that live DistributionPublishers.Remove leg is DEFERRED-TO-GATE. What
    # IS characterizable on a plain instance with no publishing configured is the branch the source
    # takes when the instance is NOT a publisher: it connects, reads the ReplicationServer's
    # IsPublisher flag, finds it false, and raises "isn't currently enabled for publishing." via
    # Stop-Function. That single leg exercises the module hop, the live connection, the
    # Get-DbaReplServer lookup, the IsPublisher branch, and the warning surface end to end. The
    # target is a standalone instance that carries no published database (InstanceMulti1); a
    # published database elsewhere in the lab makes RMO report IsPublisher = true, which would send
    # this leg down the removal branch instead.
    Context "Guarding an instance that is not a publisher" {
        It "Warns that the instance isn't currently enabled for publishing" {
            $splatDisable = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                WarningVariable = "pubWarn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $result = Disable-DbaReplPublishing @splatDisable
            $result | Should -BeNullOrEmpty
            ($pubWarn -join "`n") | Should -Match "isn't currently enabled for publishing"
        }
    }
}