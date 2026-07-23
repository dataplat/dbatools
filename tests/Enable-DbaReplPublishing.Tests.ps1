#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaReplPublishing",
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
                "SnapshotShare",
                "PublisherSqlLogin",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: actually enabling publishing requires the native RMO replication libraries
    # and an instance already configured as a distributor, which the GitHub Actions replication
    # harness provides (gh-actions-repl-*) - that live DistributionPublisher.Create leg is
    # DEFERRED-TO-GATE. What IS characterizable on a plain instance that is not a distributor is the
    # branch the source takes first: it connects, reads the ReplicationServer's IsDistributor flag,
    # finds it false, and raises "isn't currently enabled for distributing. Please enable that
    # first." via Stop-Function. That single leg exercises the module hop, the live connection, the
    # Get-DbaReplServer lookup, the IsDistributor guard, and the warning surface end to end.
    Context "Guarding an instance that is not a distributor" {
        It "Warns that the instance isn't currently enabled for distributing" {
            $splatEnable = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "distWarn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $result = Enable-DbaReplPublishing @splatEnable
            $result | Should -BeNullOrEmpty
            ($distWarn -join "`n") | Should -Match "isn't currently enabled for distributing"
        }
    }
}
