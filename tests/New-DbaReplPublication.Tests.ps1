#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaReplPublication",
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
                "Database",
                "Name",
                "Type",
                "LogReaderAgentCredential",
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
    # NOTE ON COVERAGE: creating a publication requires an instance already configured as a
    # publisher against a distributor, which the GitHub Actions replication harness provides
    # (gh-actions-repl-*) - the live TransPublication/MergePublication .Create() +
    # CreateSnapshotAgent() leg is DEFERRED-TO-GATE. What IS characterizable on a plain instance
    # with no publishing configured is the branch the source takes when the instance is NOT a
    # publisher: it connects, reads the ReplicationServer's IsPublisher flag, finds it false, and
    # raises "is not a publisher, run Enable-DbaReplPublishing to set this up" via Stop-Function,
    # then continues without constructing anything. That single leg exercises the module hop, the
    # live connection, the Get-DbaReplServer lookup, the IsPublisher guard, and the warning surface
    # end to end. The target is a standalone instance that carries no published database
    # (InstanceMulti1); a published database elsewhere in the lab makes RMO report IsPublisher =
    # true, which would send this leg down the creation branch instead.
    Context "Guarding an instance that is not a publisher" {
        It "Warns that the instance is not a publisher" {
            $splatPublication = @{
                SqlInstance     = $TestConfig.InstanceMulti1
                Database        = "master"
                Name            = "dbatoolsci_guardpub"
                Type            = "Transactional"
                WarningVariable = "pubWarn"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $result = New-DbaReplPublication @splatPublication
            $result | Should -BeNullOrEmpty
            ($pubWarn -join "`n") | Should -Match "is not a publisher"
        }
    }
}